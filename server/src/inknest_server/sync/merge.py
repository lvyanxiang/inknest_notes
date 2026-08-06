from dataclasses import dataclass
from typing import Any, Literal
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as postgresql_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.content.canonical_json import (
    content_hash,
    normalized_json_object,
)
from inknest_server.models import Folder, InfiniteCanvas, Notebook, Page
from inknest_server.repositories.content import ContentRepository
from inknest_server.repositories.library import LibraryResourceNotFoundError
from inknest_server.repositories.sync import SyncChangeRepository
from inknest_server.sync.schemas import (
    SyncMergeFolderMetadata,
    SyncMergeInfiniteCanvasMetadata,
    SyncMergeNotebookMetadata,
    SyncMergePageMetadata,
)
from inknest_server.sync.snapshots import folder_snapshot, notebook_snapshot


class SyncMergeResourceExistsError(Exception):
    def __init__(self, resource_type: str, resource_id: str) -> None:
        self.resource_type = resource_type
        self.resource_id = resource_id
        super().__init__(f"{resource_type} already exists with different metadata")


class SyncMergeParentIncompatibleError(Exception):
    def __init__(self, resource_type: str, notebook_id: str) -> None:
        self.resource_type = resource_type
        self.notebook_id = notebook_id
        super().__init__(f"{resource_type} is incompatible with its notebook layout")


@dataclass(frozen=True, slots=True)
class SyncMergeCreateResult:
    outcome: Literal["applied", "unchanged"]
    revision: int | None = None
    content_hash: str | None = None


class SyncMergeRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._changes = SyncChangeRepository(session)
        self._content = ContentRepository(session)

    async def create_folder(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        folder_id: str,
        metadata: SyncMergeFolderMetadata,
    ) -> SyncMergeCreateResult:
        inserted = await self._insert_folder(
            user_id=user_id,
            folder_id=folder_id,
            name=metadata.name,
        )
        folder = await self._session.scalar(
            select(Folder).where(Folder.id == folder_id, Folder.user_id == user_id)
        )
        if folder is None:
            raise RuntimeError("inserted merge folder disappeared")
        if not inserted:
            if folder.name != metadata.name:
                raise SyncMergeResourceExistsError("folder", folder_id)
            return SyncMergeCreateResult(outcome="unchanged")
        await self._changes.append_upsert(
            user_id=user_id,
            device_id=device_id,
            resource_type="folder",
            resource_id=folder.id,
            payload=folder_snapshot(folder),
        )
        return SyncMergeCreateResult(outcome="applied")

    async def create_notebook(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        notebook_id: str,
        metadata: SyncMergeNotebookMetadata,
    ) -> SyncMergeCreateResult:
        if metadata.folder_id is not None:
            folder = await self._session.scalar(
                select(Folder).where(
                    Folder.id == metadata.folder_id,
                    Folder.user_id == user_id,
                )
            )
            if folder is None:
                raise LibraryResourceNotFoundError("folder", metadata.folder_id)

        inserted = await self._insert_notebook(
            user_id=user_id,
            notebook_id=notebook_id,
            metadata=metadata,
        )
        notebook = await self._session.scalar(
            select(Notebook).where(
                Notebook.id == notebook_id,
                Notebook.user_id == user_id,
            )
        )
        if notebook is None:
            raise RuntimeError("inserted merge notebook disappeared")
        if not inserted:
            matches = (
                notebook.deleted_at is None
                and notebook.folder_id == metadata.folder_id
                and notebook.title == metadata.title
                and notebook.layout_mode == metadata.layout_mode
                and notebook.is_archived == metadata.is_archived
            )
            if not matches:
                raise SyncMergeResourceExistsError("notebook", notebook_id)
            return SyncMergeCreateResult(
                outcome="unchanged",
                revision=notebook.revision,
                content_hash=notebook.content_hash,
            )
        await self._changes.append_upsert(
            user_id=user_id,
            device_id=device_id,
            resource_type="notebook",
            resource_id=notebook.id,
            revision=notebook.revision,
            payload=notebook_snapshot(notebook),
        )
        return SyncMergeCreateResult(
            outcome="applied",
            revision=notebook.revision,
            content_hash=notebook.content_hash,
        )

    async def create_page(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        page_id: str,
        metadata: SyncMergePageMetadata,
    ) -> SyncMergeCreateResult:
        notebook = await self._get_parent_notebook(
            user_id=user_id,
            notebook_id=metadata.notebook_id,
        )
        if notebook.layout_mode != "paged":
            raise SyncMergeParentIncompatibleError("page", notebook.id)

        inserted = await self._insert_page(
            user_id=user_id,
            page_id=page_id,
            metadata=metadata,
        )
        page = await self._session.scalar(
            select(Page).where(Page.id == page_id, Page.user_id == user_id)
        )
        if page is None:
            raise SyncMergeResourceExistsError("page", page_id)
        normalized_content = normalized_json_object(metadata.content)
        expected_hash = content_hash(normalized_content)
        if not inserted:
            matches = (
                page.deleted_at is None
                and page.notebook_id == metadata.notebook_id
                and page.position == metadata.position
                and page.width == metadata.width
                and page.height == metadata.height
                and page.coordinate_space_version == metadata.coordinate_space_version
                and page.rotation_quarter_turns == metadata.rotation_quarter_turns
                and page.template == metadata.template
                and page.content_hash == expected_hash
                and page.content == normalized_content
            )
            if not matches:
                raise SyncMergeResourceExistsError("page", page_id)
            return SyncMergeCreateResult(
                outcome="unchanged",
                revision=page.revision,
                content_hash=page.content_hash,
            )

        saved = await self._content.save_page_content(
            user_id=user_id,
            page_id=page_id,
            base_revision=0,
            content=normalized_content,
            device_id=device_id,
        )
        return SyncMergeCreateResult(
            outcome="applied",
            revision=saved.revision,
            content_hash=saved.content_hash,
        )

    async def create_infinite_canvas(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        canvas_id: str,
        metadata: SyncMergeInfiniteCanvasMetadata,
    ) -> SyncMergeCreateResult:
        notebook = await self._get_parent_notebook(
            user_id=user_id,
            notebook_id=metadata.notebook_id,
        )
        if notebook.layout_mode != "infiniteCanvas":
            raise SyncMergeParentIncompatibleError("infinite_canvas", notebook.id)

        inserted = await self._insert_infinite_canvas(
            user_id=user_id,
            canvas_id=canvas_id,
            metadata=metadata,
        )
        canvas = await self._session.scalar(
            select(InfiniteCanvas).where(
                InfiniteCanvas.id == canvas_id,
                InfiniteCanvas.user_id == user_id,
            )
        )
        if canvas is None:
            raise SyncMergeResourceExistsError("infinite_canvas", canvas_id)
        normalized_content = normalized_json_object(metadata.content)
        expected_hash = content_hash(normalized_content)
        if not inserted:
            matches = (
                canvas.deleted_at is None
                and canvas.notebook_id == metadata.notebook_id
                and canvas.background == metadata.background
                and canvas.content_hash == expected_hash
                and canvas.content == normalized_content
            )
            if not matches:
                raise SyncMergeResourceExistsError("infinite_canvas", canvas_id)
            return SyncMergeCreateResult(
                outcome="unchanged",
                revision=canvas.revision,
                content_hash=canvas.content_hash,
            )

        saved = await self._content.save_infinite_canvas_content(
            user_id=user_id,
            canvas_id=canvas_id,
            base_revision=0,
            content=normalized_content,
            device_id=device_id,
        )
        return SyncMergeCreateResult(
            outcome="applied",
            revision=saved.revision,
            content_hash=saved.content_hash,
        )

    async def _insert_folder(self, *, user_id: UUID, folder_id: str, name: str) -> bool:
        values = {"id": folder_id, "user_id": user_id, "name": name}
        bind = self._session.get_bind()
        if bind.dialect.name == "postgresql":
            statement = (
                postgresql_insert(Folder)
                .values(**values)
                .on_conflict_do_nothing(index_elements=["id", "user_id"])
                .returning(Folder.id)
            )
        elif bind.dialect.name == "sqlite":
            statement = (
                sqlite_insert(Folder)
                .values(**values)
                .on_conflict_do_nothing(index_elements=["id", "user_id"])
                .returning(Folder.id)
            )
        else:
            raise RuntimeError("unsupported database for merge creation")
        return await self._session.scalar(statement) is not None

    async def _insert_notebook(
        self,
        *,
        user_id: UUID,
        notebook_id: str,
        metadata: SyncMergeNotebookMetadata,
    ) -> bool:
        values = {
            "id": notebook_id,
            "user_id": user_id,
            "folder_id": metadata.folder_id,
            "title": metadata.title,
            "layout_mode": metadata.layout_mode,
            "is_archived": metadata.is_archived,
        }
        bind = self._session.get_bind()
        if bind.dialect.name == "postgresql":
            statement = (
                postgresql_insert(Notebook)
                .values(**values)
                .on_conflict_do_nothing(index_elements=["id", "user_id"])
                .returning(Notebook.id)
            )
        elif bind.dialect.name == "sqlite":
            statement = (
                sqlite_insert(Notebook)
                .values(**values)
                .on_conflict_do_nothing(index_elements=["id", "user_id"])
                .returning(Notebook.id)
            )
        else:
            raise RuntimeError("unsupported database for merge creation")
        return await self._session.scalar(statement) is not None

    async def _insert_page(
        self,
        *,
        user_id: UUID,
        page_id: str,
        metadata: SyncMergePageMetadata,
    ) -> bool:
        values = {
            "id": page_id,
            "user_id": user_id,
            "notebook_id": metadata.notebook_id,
            "position": metadata.position,
            "width": metadata.width,
            "height": metadata.height,
            "coordinate_space_version": metadata.coordinate_space_version,
            "rotation_quarter_turns": metadata.rotation_quarter_turns,
            "template": metadata.template,
        }
        statement = self._insert_for_current_dialect(Page, values)
        return await self._session.scalar(statement.returning(Page.id)) is not None

    async def _insert_infinite_canvas(
        self,
        *,
        user_id: UUID,
        canvas_id: str,
        metadata: SyncMergeInfiniteCanvasMetadata,
    ) -> bool:
        values = {
            "id": canvas_id,
            "user_id": user_id,
            "notebook_id": metadata.notebook_id,
            "background": metadata.background,
        }
        statement = self._insert_for_current_dialect(InfiniteCanvas, values)
        return (
            await self._session.scalar(statement.returning(InfiniteCanvas.id))
            is not None
        )

    def _insert_for_current_dialect(
        self,
        model: type[Page] | type[InfiniteCanvas],
        values: dict[str, object],
    ) -> Any:
        bind = self._session.get_bind()
        if bind.dialect.name == "postgresql":
            return postgresql_insert(model).values(**values).on_conflict_do_nothing()
        if bind.dialect.name == "sqlite":
            return sqlite_insert(model).values(**values).on_conflict_do_nothing()
        raise RuntimeError("unsupported database for merge creation")

    async def _get_parent_notebook(
        self,
        *,
        user_id: UUID,
        notebook_id: str,
    ) -> Notebook:
        notebook = await self._session.scalar(
            select(Notebook).where(
                Notebook.id == notebook_id,
                Notebook.user_id == user_id,
                Notebook.deleted_at.is_(None),
            )
        )
        if notebook is None:
            raise LibraryResourceNotFoundError("notebook", notebook_id)
        return notebook
