from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import cast
from uuid import UUID, uuid4

import structlog
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.assets.object_keys import (
    build_asset_object_key,
    build_asset_upload_object_key,
    build_legacy_verified_object_key,
)
from inknest_server.config import Settings
from inknest_server.errors import ApiError
from inknest_server.models import Asset, AssetUpload, Notebook
from inknest_server.storage import (
    ObjectStorage,
    StoredObjectChangedError,
    StoredObjectMetadata,
    StoredObjectNotFoundError,
)

logger = structlog.get_logger(__name__)

_ALLOWED_CONTENT_TYPES = {
    "pdf": frozenset({"application/pdf"}),
    "image": frozenset(
        {"image/heic", "image/heif", "image/jpeg", "image/png", "image/webp"}
    ),
    "audio": frozenset(
        {
            "audio/aac",
            "audio/mp4",
            "audio/mpeg",
            "audio/ogg",
            "audio/wav",
            "audio/webm",
            "audio/x-wav",
        }
    ),
}
_ALLOWED_EXTENSIONS = {
    "application/pdf": frozenset({".pdf"}),
    "image/heic": frozenset({".heic"}),
    "image/heif": frozenset({".heif"}),
    "image/jpeg": frozenset({".jpeg", ".jpg"}),
    "image/png": frozenset({".png"}),
    "image/webp": frozenset({".webp"}),
    "audio/aac": frozenset({".aac"}),
    "audio/mp4": frozenset({".m4a", ".mp4"}),
    "audio/mpeg": frozenset({".mp3"}),
    "audio/ogg": frozenset({".ogg"}),
    "audio/wav": frozenset({".wav"}),
    "audio/webm": frozenset({".webm"}),
    "audio/x-wav": frozenset({".wav"}),
}


@dataclass(frozen=True, slots=True)
class UploadSessionResult:
    upload: AssetUpload
    upload_url: str


class AssetUploadService:
    def __init__(
        self,
        session: AsyncSession,
        storage: ObjectStorage,
        settings: Settings,
    ) -> None:
        self._session = session
        self._storage = storage
        self._settings = settings

    async def create_upload_session(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        notebook_id: str,
        asset_id: str,
        kind: str,
        filename: str,
        content_type: str,
        byte_size: int,
        sha256: str,
    ) -> UploadSessionResult:
        await self._ensure_notebook_owned(user_id=user_id, notebook_id=notebook_id)
        self._validate_upload(
            kind=kind,
            filename=filename,
            content_type=content_type,
            byte_size=byte_size,
        )
        if await self._asset_exists(user_id=user_id, asset_id=asset_id):
            raise ApiError(
                code="asset_already_exists",
                message="This asset already exists.",
                status_code=409,
            )

        existing = await self._find_upload(user_id=user_id, asset_id=asset_id)
        if existing is not None:
            return await self._reuse_upload(
                upload=existing,
                notebook_id=notebook_id,
                kind=kind,
                filename=filename,
                content_type=content_type,
                byte_size=byte_size,
                sha256=sha256,
            )

        now = datetime.now(UTC)
        upload_id = uuid4()
        upload = AssetUpload(
            id=upload_id,
            user_id=user_id,
            device_id=device_id,
            notebook_id=notebook_id,
            asset_id=asset_id,
            kind=kind,
            original_filename=filename,
            staging_object_key=build_asset_upload_object_key(
                user_id=str(user_id),
                upload_id=str(upload_id),
                original_filename=filename,
            ),
            content_type=content_type,
            expected_byte_size=byte_size,
            expected_sha256=sha256,
            status="pending",
            expires_at=now + timedelta(hours=self._settings.asset_upload_session_hours),
            upload_url_expires_at=now,
        )
        self._session.add(upload)
        try:
            await self._session.flush()
        except IntegrityError:
            await self._session.rollback()
            concurrent = await self._find_upload(user_id=user_id, asset_id=asset_id)
            if concurrent is None:
                raise
            return await self._reuse_upload(
                upload=concurrent,
                notebook_id=notebook_id,
                kind=kind,
                filename=filename,
                content_type=content_type,
                byte_size=byte_size,
                sha256=sha256,
            )
        return await self._sign_and_commit(upload, now=now)

    async def complete_upload_session(self, *, user_id: UUID, upload_id: UUID) -> Asset:
        upload = await self._session.scalar(
            select(AssetUpload)
            .where(
                AssetUpload.id == upload_id,
                AssetUpload.user_id == user_id,
            )
            .with_for_update()
        )
        if upload is None:
            raise ApiError(
                code="asset_upload_not_found",
                message="The asset upload session was not found.",
                status_code=404,
            )

        existing_asset = await self._get_asset(
            user_id=user_id,
            asset_id=upload.asset_id,
        )
        if upload.status == "completed":
            if existing_asset is None:
                raise ApiError(
                    code="asset_upload_state_invalid",
                    message="The completed upload has no ready asset metadata.",
                    status_code=500,
                )
            return existing_asset
        if existing_asset is not None:
            raise ApiError(
                code="asset_already_exists",
                message="This asset already exists.",
                status_code=409,
            )
        if upload.status == "cancelled":
            raise ApiError(
                code="asset_upload_cancelled",
                message="This asset upload session has been cancelled.",
                status_code=409,
            )
        if upload.status == "expired" or self._as_utc(
            upload.expires_at
        ) <= datetime.now(UTC):
            upload.status = "expired"
            await self._session.commit()
            raise ApiError(
                code="asset_upload_expired",
                message="Create the upload session again before completing it.",
                status_code=409,
            )
        if upload.status != "pending":
            raise ApiError(
                code="asset_upload_not_pending",
                message="This asset upload session is not pending.",
                status_code=409,
            )

        staging_metadata = await self._read_staging_metadata(upload)
        self._verify_metadata(upload=upload, metadata=staging_metadata)
        final_object_key = build_asset_object_key(
            user_id=str(user_id),
            notebook_id=upload.notebook_id,
            asset_id=upload.asset_id,
            kind=upload.kind,
            original_filename=upload.original_filename,
        )
        if final_object_key == upload.staging_object_key:
            final_object_key = build_legacy_verified_object_key(final_object_key)
        try:
            await self._storage.copy_object(
                upload.staging_object_key,
                final_object_key,
                source_etag=staging_metadata.etag,
            )
        except StoredObjectNotFoundError as error:
            raise self._upload_object_missing() from error
        except StoredObjectChangedError as error:
            raise ApiError(
                code="asset_upload_changed",
                message="The uploaded object changed during verification; retry.",
                status_code=409,
            ) from error

        try:
            final_metadata = await self._storage.stat_object(final_object_key)
            self._verify_metadata(upload=upload, metadata=final_metadata)
            actual_sha256 = await self._storage.calculate_sha256(final_object_key)
        except StoredObjectNotFoundError as error:
            raise self._upload_object_missing() from error
        except ApiError:
            await self._delete_object_best_effort(final_object_key)
            raise

        if actual_sha256 != upload.expected_sha256:
            await self._delete_object_best_effort(final_object_key)
            raise ApiError(
                code="asset_upload_sha256_mismatch",
                message="The uploaded object's SHA-256 does not match.",
                status_code=422,
            )

        asset = Asset(
            id=upload.asset_id,
            user_id=upload.user_id,
            notebook_id=upload.notebook_id,
            kind=upload.kind,
            original_filename=upload.original_filename,
            object_key=final_object_key,
            content_type=upload.content_type,
            byte_size=final_metadata.byte_size,
            sha256=actual_sha256,
        )
        self._session.add(asset)
        upload.status = "completed"
        upload.completed_at = datetime.now(UTC)
        await self._session.commit()
        await self._delete_object_best_effort(upload.staging_object_key)
        return asset

    async def cancel_upload_session(self, *, user_id: UUID, upload_id: UUID) -> None:
        upload = await self._session.scalar(
            select(AssetUpload).where(
                AssetUpload.id == upload_id,
                AssetUpload.user_id == user_id,
            )
        )
        if upload is None:
            raise ApiError(
                code="asset_upload_not_found",
                message="The asset upload session was not found.",
                status_code=404,
            )
        if upload.status == "cancelled":
            return
        if upload.status != "pending":
            raise ApiError(
                code="asset_upload_not_pending",
                message="Only a pending upload session can be cancelled.",
                status_code=409,
            )
        upload.status = "cancelled"
        upload.cancelled_at = datetime.now(UTC)
        await self._session.commit()

    async def _reuse_upload(
        self,
        *,
        upload: AssetUpload,
        notebook_id: str,
        kind: str,
        filename: str,
        content_type: str,
        byte_size: int,
        sha256: str,
    ) -> UploadSessionResult:
        expected = (
            upload.notebook_id,
            upload.kind,
            upload.original_filename,
            upload.content_type,
            upload.expected_byte_size,
            upload.expected_sha256,
        )
        received = (notebook_id, kind, filename, content_type, byte_size, sha256)
        if expected != received:
            raise ApiError(
                code="asset_upload_mismatch",
                message="This asset ID already has different upload metadata.",
                status_code=409,
            )
        if upload.status == "cancelled":
            raise ApiError(
                code="asset_upload_cancelled",
                message="This asset upload session has been cancelled.",
                status_code=409,
            )
        if upload.status == "expired":
            upload.status = "pending"
        if upload.status != "pending":
            raise ApiError(
                code="asset_upload_not_pending",
                message="This asset upload session is no longer pending.",
                status_code=409,
            )

        now = datetime.now(UTC)
        expected_staging_prefix = f"users/{upload.user_id}/uploads/"
        if not upload.staging_object_key.startswith(expected_staging_prefix):
            upload.staging_object_key = build_asset_upload_object_key(
                user_id=str(upload.user_id),
                upload_id=str(upload.id),
                original_filename=upload.original_filename,
            )
        if self._as_utc(upload.expires_at) <= now:
            upload.expires_at = now + timedelta(
                hours=self._settings.asset_upload_session_hours
            )
        return await self._sign_and_commit(upload, now=now)

    async def _sign_and_commit(
        self, upload: AssetUpload, *, now: datetime
    ) -> UploadSessionResult:
        session_remaining = self._as_utc(upload.expires_at) - now
        url_lifetime = min(
            timedelta(minutes=self._settings.asset_upload_url_minutes),
            session_remaining,
        )
        upload.upload_url_expires_at = now + url_lifetime
        upload_url = await self._storage.create_upload_url(
            upload.staging_object_key,
            expires=url_lifetime,
        )
        await self._session.commit()
        return UploadSessionResult(upload=upload, upload_url=upload_url)

    async def _ensure_notebook_owned(self, *, user_id: UUID, notebook_id: str) -> None:
        notebook = await self._session.scalar(
            select(Notebook).where(
                Notebook.id == notebook_id,
                Notebook.user_id == user_id,
            )
        )
        if notebook is None:
            raise ApiError(
                code="notebook_not_found",
                message="The notebook was not found.",
                status_code=404,
            )

    async def _asset_exists(self, *, user_id: UUID, asset_id: str) -> bool:
        asset = await self._session.scalar(
            select(Asset.id).where(Asset.id == asset_id, Asset.user_id == user_id)
        )
        return asset is not None

    async def _find_upload(self, *, user_id: UUID, asset_id: str) -> AssetUpload | None:
        return cast(
            AssetUpload | None,
            await self._session.scalar(
                select(AssetUpload).where(
                    AssetUpload.user_id == user_id,
                    AssetUpload.asset_id == asset_id,
                )
            ),
        )

    async def _get_asset(self, *, user_id: UUID, asset_id: str) -> Asset | None:
        return cast(
            Asset | None,
            await self._session.scalar(
                select(Asset).where(
                    Asset.user_id == user_id,
                    Asset.id == asset_id,
                )
            ),
        )

    async def _read_staging_metadata(self, upload: AssetUpload) -> StoredObjectMetadata:
        try:
            return await self._storage.stat_object(upload.staging_object_key)
        except StoredObjectNotFoundError as error:
            raise self._upload_object_missing() from error

    @staticmethod
    def _verify_metadata(
        *, upload: AssetUpload, metadata: StoredObjectMetadata
    ) -> None:
        if metadata.byte_size != upload.expected_byte_size:
            raise ApiError(
                code="asset_upload_size_mismatch",
                message="The uploaded object's size does not match.",
                status_code=422,
                details={
                    "expectedBytes": upload.expected_byte_size,
                    "actualBytes": metadata.byte_size,
                },
            )
        actual_content_type = metadata.content_type.split(";", maxsplit=1)[0].lower()
        if actual_content_type != upload.content_type:
            raise ApiError(
                code="asset_upload_content_type_mismatch",
                message="The uploaded object's content type does not match.",
                status_code=422,
            )

    async def _delete_object_best_effort(self, object_key: str) -> None:
        try:
            await self._storage.delete_object(object_key)
        except Exception as error:
            await logger.awarning(
                "asset_object_cleanup_failed",
                object_key=object_key,
                error_type=type(error).__name__,
            )

    @staticmethod
    def _upload_object_missing() -> ApiError:
        return ApiError(
            code="asset_upload_object_missing",
            message="Upload the object before completing this session.",
            status_code=409,
        )

    def _validate_upload(
        self,
        *,
        kind: str,
        filename: str,
        content_type: str,
        byte_size: int,
    ) -> None:
        if content_type not in _ALLOWED_CONTENT_TYPES[kind]:
            raise ApiError(
                code="unsupported_asset_media_type",
                message="The content type is not supported for this asset kind.",
                status_code=415,
            )
        normalized_filename = filename.replace("\\", "/").rsplit("/", maxsplit=1)[-1]
        extension = (
            f".{normalized_filename.rsplit('.', maxsplit=1)[-1].lower()}"
            if "." in normalized_filename
            else ""
        )
        if extension not in _ALLOWED_EXTENSIONS[content_type]:
            raise ApiError(
                code="unsupported_asset_extension",
                message="The filename extension does not match the content type.",
                status_code=415,
            )
        if byte_size > self._settings.max_asset_upload_bytes:
            raise ApiError(
                code="asset_too_large",
                message="The asset exceeds the maximum allowed size.",
                status_code=413,
                details={"maxBytes": self._settings.max_asset_upload_bytes},
            )

    @staticmethod
    def _as_utc(value: datetime) -> datetime:
        return value.replace(tzinfo=UTC) if value.tzinfo is None else value
