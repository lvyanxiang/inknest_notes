from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.models import Folder, Notebook


@dataclass(frozen=True, slots=True)
class SyncLibraryInventory:
    folder_ids: list[str]
    notebook_ids: list[str]

    @property
    def has_cloud_library(self) -> bool:
        return bool(self.folder_ids or self.notebook_ids)


class SyncBootstrapRepository:
    """Read the active, account-scoped library roots used before first merge."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def read_inventory(self, *, user_id: UUID) -> SyncLibraryInventory:
        folder_ids = await self._session.scalars(
            select(Folder.id).where(Folder.user_id == user_id).order_by(Folder.id)
        )
        notebook_ids = await self._session.scalars(
            select(Notebook.id)
            .where(Notebook.user_id == user_id, Notebook.deleted_at.is_(None))
            .order_by(Notebook.id)
        )
        return SyncLibraryInventory(
            folder_ids=list(folder_ids),
            notebook_ids=list(notebook_ids),
        )
