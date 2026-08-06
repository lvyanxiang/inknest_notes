from dataclasses import asdict, dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.config import Settings
from inknest_server.models import (
    Asset,
    AssetGarbageCollectionCandidate,
    AssetUpload,
)
from inknest_server.storage import ObjectStorage

logger = structlog.get_logger(__name__)
_FINAL_ASSET_DIRECTORIES = frozenset({"pdfs", "images", "audio"})


@dataclass(slots=True)
class AssetCleanupSummary:
    mode: str
    expired_sessions: int = 0
    eligible_staging_objects: int = 0
    deleted_staging_objects: int = 0
    discovered_orphan_objects: int = 0
    eligible_orphan_objects: int = 0
    deleted_orphan_objects: int = 0
    protected_objects: int = 0
    failures: int = 0

    def to_dict(self) -> dict[str, str | int]:
        return asdict(self)


class AssetCleanupService:
    def __init__(
        self,
        session: AsyncSession,
        storage: ObjectStorage,
        settings: Settings,
    ) -> None:
        self._session = session
        self._storage = storage
        self._settings = settings

    async def run(
        self,
        *,
        execute: bool,
        now: datetime | None = None,
        object_prefix: str = "users/",
    ) -> AssetCleanupSummary:
        observed_at = self._as_utc(now or datetime.now(UTC))
        summary = AssetCleanupSummary(mode="execute" if execute else "dry-run")

        expired_uploads = list(
            (
                await self._session.scalars(
                    select(AssetUpload)
                    .where(
                        AssetUpload.status == "pending",
                        AssetUpload.expires_at <= observed_at,
                    )
                    .order_by(AssetUpload.expires_at, AssetUpload.id)
                    .limit(self._settings.asset_cleanup_batch_size)
                )
            ).all()
        )
        summary.expired_sessions = len(expired_uploads)
        if execute:
            for upload in expired_uploads:
                upload.status = "expired"

        staging_uploads = await self._eligible_staging_uploads(observed_at)
        summary.eligible_staging_objects = len(staging_uploads)
        if execute:
            for upload in staging_uploads:
                await self._delete_staging_object(
                    upload=upload,
                    observed_at=observed_at,
                    summary=summary,
                )

        await self._discover_orphans(
            observed_at=observed_at,
            execute=execute,
            object_prefix=object_prefix,
            summary=summary,
        )
        await self._delete_eligible_orphans(
            observed_at=observed_at,
            execute=execute,
            summary=summary,
        )

        if execute:
            await self._session.commit()
        else:
            await self._session.rollback()
        return summary

    async def _eligible_staging_uploads(
        self, observed_at: datetime
    ) -> list[AssetUpload]:
        pending_cutoff = observed_at - timedelta(
            hours=self._settings.asset_cleanup_pending_grace_hours
        )
        staging_cutoff = observed_at - timedelta(
            hours=self._settings.asset_cleanup_staging_grace_hours
        )
        return list(
            (
                await self._session.scalars(
                    select(AssetUpload)
                    .where(
                        AssetUpload.staging_deleted_at.is_(None),
                        or_(
                            (
                                (AssetUpload.status == "expired")
                                & (AssetUpload.expires_at <= pending_cutoff)
                            ),
                            (
                                (AssetUpload.status == "pending")
                                & (AssetUpload.expires_at <= pending_cutoff)
                            ),
                            (
                                (AssetUpload.status == "cancelled")
                                & (AssetUpload.cancelled_at <= staging_cutoff)
                            ),
                            (
                                (AssetUpload.status == "completed")
                                & (AssetUpload.completed_at <= staging_cutoff)
                            ),
                        ),
                    )
                    .order_by(AssetUpload.expires_at, AssetUpload.id)
                    .limit(self._settings.asset_cleanup_batch_size)
                )
            ).all()
        )

    async def _delete_staging_object(
        self,
        *,
        upload: AssetUpload,
        observed_at: datetime,
        summary: AssetCleanupSummary,
    ) -> None:
        expected_prefix = f"users/{upload.user_id}/uploads/"
        upload.cleanup_attempts += 1
        if not upload.staging_object_key.startswith(expected_prefix):
            upload.last_cleanup_error = "unsafe staging object key"
            summary.failures += 1
            return
        try:
            await self._storage.delete_object(upload.staging_object_key)
        except Exception as error:
            upload.last_cleanup_error = type(error).__name__[:512]
            summary.failures += 1
            await logger.awarning(
                "asset_staging_cleanup_failed",
                upload_id=str(upload.id),
                error_type=type(error).__name__,
            )
            return
        upload.staging_deleted_at = observed_at
        upload.last_cleanup_error = None
        summary.deleted_staging_objects += 1

    async def _discover_orphans(
        self,
        *,
        observed_at: datetime,
        execute: bool,
        object_prefix: str,
        summary: AssetCleanupSummary,
    ) -> None:
        listed_keys = await self._storage.list_object_keys(object_prefix)
        final_keys = [key for key in listed_keys if self._is_safe_final_key(key)]
        if not final_keys:
            return

        referenced_keys = set(
            (
                await self._session.scalars(
                    select(Asset.object_key).where(Asset.object_key.in_(final_keys))
                )
            ).all()
        )
        candidate_keys = [key for key in final_keys if key not in referenced_keys]
        summary.discovered_orphan_objects = min(
            len(candidate_keys), self._settings.asset_cleanup_batch_size
        )
        if not execute:
            return

        candidate_keys = candidate_keys[: self._settings.asset_cleanup_batch_size]
        existing = {
            candidate.object_key: candidate
            for candidate in (
                await self._session.scalars(
                    select(AssetGarbageCollectionCandidate).where(
                        AssetGarbageCollectionCandidate.object_key.in_(candidate_keys)
                    )
                )
            ).all()
        }
        quarantine = timedelta(days=self._settings.asset_cleanup_orphan_quarantine_days)
        for object_key in candidate_keys:
            candidate = existing.get(object_key)
            if candidate is None:
                self._session.add(
                    AssetGarbageCollectionCandidate(
                        object_key=object_key,
                        reason="orphan_final_object",
                        status="pending",
                        first_seen_at=observed_at,
                        eligible_after=observed_at + quarantine,
                        last_checked_at=observed_at,
                    )
                )
            elif candidate.status == "protected":
                candidate.status = "pending"
                candidate.first_seen_at = observed_at
                candidate.eligible_after = observed_at + quarantine
                candidate.last_checked_at = observed_at
                candidate.last_error = None

    async def _delete_eligible_orphans(
        self,
        *,
        observed_at: datetime,
        execute: bool,
        summary: AssetCleanupSummary,
    ) -> None:
        candidates = list(
            (
                await self._session.scalars(
                    select(AssetGarbageCollectionCandidate)
                    .where(
                        AssetGarbageCollectionCandidate.status == "pending",
                        AssetGarbageCollectionCandidate.eligible_after <= observed_at,
                    )
                    .order_by(
                        AssetGarbageCollectionCandidate.eligible_after,
                        AssetGarbageCollectionCandidate.id,
                    )
                    .limit(self._settings.asset_cleanup_batch_size)
                )
            ).all()
        )
        summary.eligible_orphan_objects = len(candidates)
        if not execute:
            return

        for candidate in candidates:
            candidate.last_checked_at = observed_at
            referenced = await self._session.scalar(
                select(Asset.object_key).where(Asset.object_key == candidate.object_key)
            )
            if referenced is not None:
                candidate.status = "protected"
                candidate.last_error = None
                summary.protected_objects += 1
                continue
            if not self._is_safe_final_key(candidate.object_key):
                candidate.status = "protected"
                candidate.last_error = "unsafe final object key"
                summary.protected_objects += 1
                continue

            candidate.delete_attempts += 1
            try:
                await self._storage.delete_object(candidate.object_key)
            except Exception as error:
                candidate.last_error = type(error).__name__[:512]
                summary.failures += 1
                await logger.awarning(
                    "asset_orphan_cleanup_failed",
                    candidate_id=str(candidate.id),
                    error_type=type(error).__name__,
                )
                continue
            candidate.status = "deleted"
            candidate.deleted_at = observed_at
            candidate.last_error = None
            summary.deleted_orphan_objects += 1

    @staticmethod
    def _is_safe_final_key(object_key: str) -> bool:
        parts = object_key.split("/")
        if (
            len(parts) < 7
            or parts[0] != "users"
            or parts[2] != "notebooks"
            or parts[4] not in _FINAL_ASSET_DIRECTORIES
        ):
            return False
        try:
            UUID(parts[1])
        except ValueError:
            return False
        return bool(parts[3] and parts[4] and parts[5] and parts[6])

    @staticmethod
    def _as_utc(value: datetime) -> datetime:
        if value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value.astimezone(UTC)
