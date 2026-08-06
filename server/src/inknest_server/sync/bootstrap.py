from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.models import Folder, InfiniteCanvas, Notebook, Page


@dataclass(frozen=True, slots=True)
class SyncLibraryInventory:
    folders: list[Folder]
    notebooks: list[Notebook]
    pages: list[Page]
    infinite_canvases: list[InfiniteCanvas]

    @property
    def folder_ids(self) -> list[str]:
        return [folder.id for folder in self.folders]

    @property
    def notebook_ids(self) -> list[str]:
        return [notebook.id for notebook in self.notebooks]

    @property
    def has_cloud_library(self) -> bool:
        return bool(
            self.folder_ids or self.notebook_ids or self.pages or self.infinite_canvases
        )


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
        pages = await self._session.scalars(
            select(Page)
            .join(
                Notebook,
                and_(
                    Notebook.id == Page.notebook_id,
                    Notebook.user_id == Page.user_id,
                ),
            )
            .where(
                Page.user_id == user_id,
                Page.deleted_at.is_(None),
                Notebook.deleted_at.is_(None),
            )
            .order_by(Page.notebook_id, Page.position, Page.id)
        )
        infinite_canvases = await self._session.scalars(
            select(InfiniteCanvas)
            .join(
                Notebook,
                and_(
                    Notebook.id == InfiniteCanvas.notebook_id,
                    Notebook.user_id == InfiniteCanvas.user_id,
                ),
            )
            .where(
                InfiniteCanvas.user_id == user_id,
                InfiniteCanvas.deleted_at.is_(None),
                Notebook.deleted_at.is_(None),
            )
            .order_by(InfiniteCanvas.notebook_id, InfiniteCanvas.id)
        )
        return SyncLibraryInventory(
            folders=list(folders),
            notebooks=list(notebooks),
            pages=list(pages),
            infinite_canvases=list(infinite_canvases),
        )
