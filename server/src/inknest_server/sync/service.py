from dataclasses import dataclass
from uuid import UUID

from inknest_server.models import SyncChange
from inknest_server.repositories.sync import SyncChangeRepository
from inknest_server.sync.cursor import SyncCursorCodec


@dataclass(frozen=True, slots=True)
class SyncChangePage:
    changes: list[SyncChange]
    next_cursor: str
    has_more: bool


class SyncService:
    def __init__(
        self,
        repository: SyncChangeRepository,
        cursor_codec: SyncCursorCodec,
    ) -> None:
        self._repository = repository
        self._cursor_codec = cursor_codec

    async def list_changes(
        self,
        *,
        user_id: UUID,
        cursor: str | None,
        limit: int,
    ) -> SyncChangePage:
        after_sequence = (
            self._cursor_codec.decode(cursor, user_id=user_id)
            if cursor is not None
            else 0
        )
        rows = await self._repository.list_after(
            user_id=user_id,
            after_sequence=after_sequence,
            limit=limit + 1,
        )
        has_more = len(rows) > limit
        changes = rows[:limit]
        next_sequence = changes[-1].sequence if changes else after_sequence
        return SyncChangePage(
            changes=changes,
            next_cursor=self._cursor_codec.encode(
                user_id=user_id,
                sequence=next_sequence,
            ),
            has_more=has_more,
        )
