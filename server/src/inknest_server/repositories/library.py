from uuid import UUID

from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.models.library import (
    Asset,
    Folder,
    InfiniteCanvas,
    Notebook,
    Page,
)
from inknest_server.repositories.sync import SyncChangeRepository
from inknest_server.sync.snapshots import (
    asset_snapshot,
    folder_snapshot,
    infinite_canvas_snapshot,
    notebook_snapshot,
    page_snapshot,
)

VALID_LAYOUT_MODES = frozenset({"paged", "infiniteCanvas"})


class LibraryResourceNotFoundError(Exception):
    def __init__(self, resource_type: str, resource_id: str) -> None:
        super().__init__(f"{resource_type} not found: {resource_id}")


class InvalidLibraryOperationError(Exception):
    pass


class LibraryRepository:
    """Persist library metadata while enforcing the current user's ownership."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._changes = SyncChangeRepository(session)

    async def create_folder(
        self, *, user_id: UUID, folder_id: str, name: str
    ) -> Folder:
        folder = Folder(id=folder_id, user_id=user_id, name=name)
        self._session.add(folder)
        await self._session.flush()
        await self._changes.append_upsert(
            user_id=user_id,
            resource_type="folder",
            resource_id=folder.id,
            payload=folder_snapshot(folder),
        )
        return folder

    async def get_folder(self, *, user_id: UUID, folder_id: str) -> Folder:
        statement = select(Folder).where(
            Folder.id == folder_id, Folder.user_id == user_id
        )
        return await self._one_owned(statement, "folder", folder_id)

    async def list_folders(self, *, user_id: UUID) -> list[Folder]:
        result = await self._session.scalars(
            select(Folder)
            .where(Folder.user_id == user_id)
            .order_by(Folder.updated_at.desc(), Folder.id)
        )
        return list(result)

    async def create_notebook(
        self,
        *,
        user_id: UUID,
        notebook_id: str,
        title: str,
        layout_mode: str,
        folder_id: str | None = None,
        is_archived: bool = False,
    ) -> Notebook:
        if layout_mode not in VALID_LAYOUT_MODES:
            raise InvalidLibraryOperationError(
                f"Unsupported notebook layout mode: {layout_mode}"
            )
        if folder_id is not None:
            await self.get_folder(user_id=user_id, folder_id=folder_id)

        notebook = Notebook(
            id=notebook_id,
            user_id=user_id,
            folder_id=folder_id,
            title=title,
            layout_mode=layout_mode,
            is_archived=is_archived,
        )
        self._session.add(notebook)
        await self._session.flush()
        await self._changes.append_upsert(
            user_id=user_id,
            resource_type="notebook",
            resource_id=notebook.id,
            payload=notebook_snapshot(notebook),
            revision=notebook.revision,
        )
        return notebook

    async def get_notebook(self, *, user_id: UUID, notebook_id: str) -> Notebook:
        statement = select(Notebook).where(
            Notebook.id == notebook_id,
            Notebook.user_id == user_id,
            Notebook.deleted_at.is_(None),
        )
        return await self._one_owned(statement, "notebook", notebook_id)

    async def list_notebooks(self, *, user_id: UUID) -> list[Notebook]:
        result = await self._session.scalars(
            select(Notebook)
            .where(Notebook.user_id == user_id, Notebook.deleted_at.is_(None))
            .order_by(Notebook.updated_at.desc(), Notebook.id)
        )
        return list(result)

    async def create_page(
        self,
        *,
        user_id: UUID,
        notebook_id: str,
        page_id: str,
        position: int,
        width: float,
        height: float,
        coordinate_space_version: object,
        rotation_quarter_turns: int = 0,
        template: str = "blank",
    ) -> Page:
        notebook = await self.get_notebook(user_id=user_id, notebook_id=notebook_id)
        if notebook.layout_mode != "paged":
            raise InvalidLibraryOperationError(
                "Pages can only be added to paged notebooks"
            )

        page = Page(
            id=page_id,
            user_id=user_id,
            notebook_id=notebook_id,
            position=position,
            width=width,
            height=height,
            coordinate_space_version=coordinate_space_version,
            rotation_quarter_turns=rotation_quarter_turns,
            template=template,
        )
        self._session.add(page)
        await self._session.flush()
        await self._changes.append_upsert(
            user_id=user_id,
            resource_type="page",
            resource_id=page.id,
            payload=page_snapshot(page),
            revision=page.revision,
        )
        return page

    async def get_page(self, *, user_id: UUID, page_id: str) -> Page:
        statement = select(Page).where(
            Page.id == page_id,
            Page.user_id == user_id,
            Page.deleted_at.is_(None),
        )
        return await self._one_owned(statement, "page", page_id)

    async def list_pages(self, *, user_id: UUID, notebook_id: str) -> list[Page]:
        await self.get_notebook(user_id=user_id, notebook_id=notebook_id)
        result = await self._session.scalars(
            select(Page)
            .where(
                Page.user_id == user_id,
                Page.notebook_id == notebook_id,
                Page.deleted_at.is_(None),
            )
            .order_by(Page.position)
        )
        return list(result)

    async def create_infinite_canvas(
        self,
        *,
        user_id: UUID,
        notebook_id: str,
        canvas_id: str,
        background: str = "blank",
    ) -> InfiniteCanvas:
        notebook = await self.get_notebook(user_id=user_id, notebook_id=notebook_id)
        if notebook.layout_mode != "infiniteCanvas":
            raise InvalidLibraryOperationError(
                "Infinite canvases require an infiniteCanvas notebook"
            )

        canvas = InfiniteCanvas(
            id=canvas_id,
            user_id=user_id,
            notebook_id=notebook_id,
            background=background,
        )
        self._session.add(canvas)
        await self._session.flush()
        await self._changes.append_upsert(
            user_id=user_id,
            resource_type="infinite_canvas",
            resource_id=canvas.id,
            payload=infinite_canvas_snapshot(canvas),
            revision=canvas.revision,
        )
        return canvas

    async def get_infinite_canvas(
        self, *, user_id: UUID, canvas_id: str
    ) -> InfiniteCanvas:
        statement = select(InfiniteCanvas).where(
            InfiniteCanvas.id == canvas_id,
            InfiniteCanvas.user_id == user_id,
            InfiniteCanvas.deleted_at.is_(None),
        )
        return await self._one_owned(statement, "infinite canvas", canvas_id)

    async def create_asset_metadata(
        self,
        *,
        user_id: UUID,
        notebook_id: str,
        asset_id: str,
        kind: str,
        original_filename: str,
        relative_path: str,
        object_key: str,
        content_type: str,
        byte_size: int,
        sha256: str,
    ) -> Asset:
        await self.get_notebook(user_id=user_id, notebook_id=notebook_id)
        asset = Asset(
            id=asset_id,
            user_id=user_id,
            notebook_id=notebook_id,
            kind=kind,
            original_filename=original_filename,
            relative_path=relative_path,
            object_key=object_key,
            content_type=content_type,
            byte_size=byte_size,
            sha256=sha256,
        )
        self._session.add(asset)
        await self._session.flush()
        await self._changes.append_upsert(
            user_id=user_id,
            resource_type="asset",
            resource_id=asset.id,
            payload=asset_snapshot(asset),
        )
        return asset

    async def get_asset(self, *, user_id: UUID, asset_id: str) -> Asset:
        statement = select(Asset).where(Asset.id == asset_id, Asset.user_id == user_id)
        return await self._one_owned(statement, "asset", asset_id)

    async def _one_owned[ModelType: (Asset, Folder, InfiniteCanvas, Notebook, Page)](
        self,
        statement: Select[tuple[ModelType]],
        resource_type: str,
        resource_id: str,
    ) -> ModelType:
        resource = await self._session.scalar(statement)
        if resource is None:
            raise LibraryResourceNotFoundError(resource_type, resource_id)
        return resource
