from dataclasses import dataclass
from typing import Literal
from uuid import UUID, uuid4

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as postgresql_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.models import SyncChange, SyncCommit

SyncResourceType = Literal[
    "folder", "notebook", "page", "infinite_canvas", "asset", "conflict"
]


class SyncIdempotencyKeyReusedError(Exception):
    pass


@dataclass(frozen=True, slots=True)
class SyncCommitReservation:
    record: SyncCommit
    replayed: bool


class SyncChangeRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def append_upsert(
        self,
        *,
        user_id: UUID,
        resource_type: SyncResourceType,
        resource_id: str,
        payload: dict[str, object],
        revision: int | None = None,
        content_hash: str | None = None,
        device_id: UUID | None = None,
    ) -> SyncChange:
        change = SyncChange(
            user_id=user_id,
            device_id=device_id,
            resource_type=resource_type,
            resource_id=resource_id,
            operation="upsert",
            revision=revision,
            content_hash=content_hash,
            payload=payload,
        )
        self._session.add(change)
        await self._session.flush()
        return change

    async def list_after(
        self,
        *,
        user_id: UUID,
        after_sequence: int,
        limit: int,
    ) -> list[SyncChange]:
        if after_sequence < 0:
            raise ValueError("after_sequence must be non-negative")
        if limit < 1:
            raise ValueError("limit must be positive")
        changes = await self._session.scalars(
            select(SyncChange)
            .where(
                SyncChange.user_id == user_id,
                SyncChange.sequence > after_sequence,
            )
            .order_by(SyncChange.sequence)
            .limit(limit)
        )
        return list(changes)

    async def latest_sequence(self, *, user_id: UUID) -> int:
        sequence = await self._session.scalar(
            select(func.max(SyncChange.sequence)).where(SyncChange.user_id == user_id)
        )
        return sequence or 0


class SyncCommitRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def reserve(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        idempotency_key: str,
        request_hash: str,
    ) -> SyncCommitReservation:
        existing = await self._find(
            user_id=user_id,
            device_id=device_id,
            idempotency_key=idempotency_key,
            lock=True,
        )
        if existing is not None:
            return self._existing(existing, request_hash=request_hash)

        record_id = uuid4()
        values = {
            "id": record_id,
            "user_id": user_id,
            "device_id": device_id,
            "idempotency_key": idempotency_key,
            "request_hash": request_hash,
            "response_payload": {},
        }
        bind = self._session.get_bind()
        if bind.dialect.name == "postgresql":
            statement = (
                postgresql_insert(SyncCommit)
                .values(**values)
                .on_conflict_do_nothing(
                    index_elements=["user_id", "device_id", "idempotency_key"]
                )
                .returning(SyncCommit.id)
            )
        elif bind.dialect.name == "sqlite":
            statement = (
                sqlite_insert(SyncCommit)
                .values(**values)
                .on_conflict_do_nothing(
                    index_elements=["user_id", "device_id", "idempotency_key"]
                )
                .returning(SyncCommit.id)
            )
        else:
            raise RuntimeError("unsupported database for idempotent synchronization")

        inserted_id = await self._session.scalar(statement)
        if inserted_id is None:
            existing = await self._find(
                user_id=user_id,
                device_id=device_id,
                idempotency_key=idempotency_key,
                lock=True,
            )
            if existing is None:
                raise RuntimeError("synchronization commit reservation disappeared")
            return self._existing(existing, request_hash=request_hash)
        record = await self._session.get(SyncCommit, inserted_id)
        if record is None:
            raise RuntimeError("synchronization commit reservation was not persisted")
        return SyncCommitReservation(record=record, replayed=False)

    async def _find(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        idempotency_key: str,
        lock: bool,
    ) -> SyncCommit | None:
        statement = select(SyncCommit).where(
            SyncCommit.user_id == user_id,
            SyncCommit.device_id == device_id,
            SyncCommit.idempotency_key == idempotency_key,
        )
        if lock:
            statement = statement.with_for_update()
        result: SyncCommit | None = await self._session.scalar(statement)
        return result

    @staticmethod
    def _existing(record: SyncCommit, *, request_hash: str) -> SyncCommitReservation:
        if record.request_hash != request_hash:
            raise SyncIdempotencyKeyReusedError
        return SyncCommitReservation(record=record, replayed=True)
