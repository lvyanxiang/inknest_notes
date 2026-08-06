from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.models import Folder, Notebook


@dataclass(frozen=True, slots=True)
class SyncLibraryInventory:
    folders: list[Folder]
    notebooks: list[Notebook]

    @property
    def folder_ids(self) -> list[str]:
        return [folder.id for folder in self.folders]

    @property
    def notebook_ids(self) -> list[str]:
        return [notebook.id for notebook in self.notebooks]

    @property
    def has_cloud_library(self) -> bool:
        return bool(self.folder_ids or self.notebook_ids)


class SyncBootstrapRepository:
    """Read the active, account-scoped library roots used before first merge."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def read_inventory(self, *, user_id: UUID) -> SyncLibraryInventory:
        folders = await self._session.scalars(
            select(Folder).where(Folder.user_id == user_id).order_by(Folder.id)
        )
        notebooks = await self._session.scalars(
            select(Notebook)
            .where(Notebook.user_id == user_id, Notebook.deleted_at.is_(None))
            .order_by(Notebook.id)
        )
        return SyncLibraryInventory(
            folders=list(folders),
            notebooks=list(notebooks),
        )
