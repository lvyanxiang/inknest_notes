from dataclasses import dataclass
from typing import Literal
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as postgresql_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.models import Folder, Notebook
from inknest_server.repositories.library import LibraryResourceNotFoundError
from inknest_server.repositories.sync import SyncChangeRepository
from inknest_server.sync.schemas import (
    SyncMergeFolderMetadata,
    SyncMergeNotebookMetadata,
)
from inknest_server.sync.snapshots import folder_snapshot, notebook_snapshot


class SyncMergeResourceExistsError(Exception):
    def __init__(self, resource_type: str, resource_id: str) -> None:
        self.resource_type = resource_type
        self.resource_id = resource_id
        super().__init__(f"{resource_type} already exists with different metadata")


@dataclass(frozen=True, slots=True)
class SyncMergeCreateResult:
    outcome: Literal["applied", "unchanged"]


class SyncMergeRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._changes = SyncChangeRepository(session)

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
            return SyncMergeCreateResult(outcome="unchanged")
        await self._changes.append_upsert(
            user_id=user_id,
            device_id=device_id,
            resource_type="notebook",
            resource_id=notebook.id,
            revision=notebook.revision,
            payload=notebook_snapshot(notebook),
        )
        return SyncMergeCreateResult(outcome="applied")

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
