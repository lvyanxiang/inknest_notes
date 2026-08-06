from typing import Literal
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.models import SyncChange

SyncResourceType = Literal["folder", "notebook", "page", "infinite_canvas", "asset"]


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
