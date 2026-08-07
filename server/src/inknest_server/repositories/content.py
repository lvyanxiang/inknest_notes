from dataclasses import dataclass
from typing import Literal
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.content.canonical_json import (
    content_hash as calculate_content_hash,
)
from inknest_server.content.canonical_json import normalized_json_object
from inknest_server.models.auth import Device
from inknest_server.models.library import (
    ContentRevision,
    Folder,
    InfiniteCanvas,
    Notebook,
    Page,
)
from inknest_server.repositories.library import LibraryResourceNotFoundError
from inknest_server.repositories.sync import SyncChangeRepository
from inknest_server.sync.snapshots import (
    folder_snapshot,
    infinite_canvas_snapshot,
    notebook_snapshot,
    page_snapshot,
)

ResourceType = Literal["notebook", "page", "infinite_canvas"]
RevisionedResource = Notebook | Page | InfiniteCanvas


class RevisionConflictError(Exception):
    def __init__(self, *, expected_revision: int, current_revision: int) -> None:
        self.expected_revision = expected_revision
        self.current_revision = current_revision
        super().__init__(
            "content revision conflict: "
            f"expected {expected_revision}, current {current_revision}"
        )


class ResourceDeletedError(Exception):
    def __init__(self, *, current_revision: int) -> None:
        self.current_revision = current_revision
        super().__init__("the resource is soft-deleted")


class NotebookMetadataConflictError(Exception):
    def __init__(self, fields: list[str]) -> None:
        self.fields = fields
        super().__init__("notebook metadata changed concurrently")


class FolderMetadataConflictError(Exception):
    pass


@dataclass(frozen=True, slots=True)
class ContentSaveResult:
    revision: int
    content_hash: str
    created_revision: bool


class ContentRepository:
    """Store immutable JSON revisions and one locked current-content snapshot."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._changes = SyncChangeRepository(session)

    async def save_folder(
        self,
        *,
        user_id: UUID,
        folder_id: str,
        base_revision: int,
        metadata: dict[str, object],
        base_metadata: dict[str, object] | None,
        device_id: UUID | None = None,
    ) -> ContentSaveResult:
        if device_id is not None:
            await self._ensure_active_device_owned(user_id=user_id, device_id=device_id)
        desired_name = str(metadata["name"])
        desired_hash = calculate_content_hash({"name": desired_name})
        folder = await self._session.scalar(
            select(Folder)
            .where(Folder.id == folder_id, Folder.user_id == user_id)
            .with_for_update()
        )
        if folder is None:
            if base_revision != 0 or base_metadata is not None:
                raise LibraryResourceNotFoundError("folder", folder_id)
            folder = Folder(
                id=folder_id,
                user_id=user_id,
                name=desired_name,
                revision=1,
                content_hash=desired_hash,
            )
            self._session.add(folder)
            await self._session.flush()
            await self._changes.append_upsert(
                user_id=user_id,
                resource_type="folder",
                resource_id=folder.id,
                payload=folder_snapshot(folder),
                revision=folder.revision,
                content_hash=folder.content_hash,
                device_id=device_id,
            )
            return ContentSaveResult(
                revision=folder.revision,
                content_hash=folder.content_hash,
                created_revision=True,
            )

        if base_metadata is None:
            if folder.name != desired_name:
                raise FolderMetadataConflictError
            if folder.revision == 0:
                folder.revision = 1
                folder.content_hash = desired_hash
                await self._session.flush()
                await self._changes.append_upsert(
                    user_id=user_id,
                    resource_type="folder",
                    resource_id=folder.id,
                    payload=folder_snapshot(folder),
                    revision=folder.revision,
                    content_hash=folder.content_hash,
                    device_id=device_id,
                )
                return ContentSaveResult(
                    revision=folder.revision,
                    content_hash=folder.content_hash,
                    created_revision=True,
                )
            return ContentSaveResult(
                revision=folder.revision,
                content_hash=folder.content_hash,
                created_revision=False,
            )

        baseline_name = str(base_metadata["name"])
        if desired_name == baseline_name or folder.name == desired_name:
            return ContentSaveResult(
                revision=folder.revision,
                content_hash=folder.content_hash,
                created_revision=False,
            )
        if folder.name != baseline_name or folder.revision != base_revision:
            raise FolderMetadataConflictError

        folder.name = desired_name
        folder.revision += 1
        folder.content_hash = desired_hash
        await self._session.flush()
        await self._changes.append_upsert(
            user_id=user_id,
            resource_type="folder",
            resource_id=folder.id,
            payload=folder_snapshot(folder),
            revision=folder.revision,
            content_hash=folder.content_hash,
            device_id=device_id,
        )
        return ContentSaveResult(
            revision=folder.revision,
            content_hash=folder.content_hash,
            created_revision=True,
        )

    async def delete_folder(
        self,
        *,
        user_id: UUID,
        folder_id: str,
        base_revision: int,
        device_id: UUID,
    ) -> ContentSaveResult:
        """Delete an organizer after moving every contained notebook to root."""
        await self._ensure_active_device_owned(user_id=user_id, device_id=device_id)
        folder = await self._session.scalar(
            select(Folder)
            .where(Folder.id == folder_id, Folder.user_id == user_id)
            .with_for_update()
        )
        if folder is None:
            raise LibraryResourceNotFoundError("folder", folder_id)
        if folder.revision != base_revision:
            raise RevisionConflictError(
                expected_revision=base_revision,
                current_revision=folder.revision,
            )

        notebooks = list(
            await self._session.scalars(
                select(Notebook)
                .where(
                    Notebook.user_id == user_id,
                    Notebook.folder_id == folder_id,
                )
                .with_for_update()
            )
        )
        for notebook in notebooks:
            if notebook.deleted_at is not None:
                notebook.folder_id = None
                continue
            next_revision = notebook.revision + 1
            next_hash = (
                notebook.content_hash
                if notebook.revision > 0
                else calculate_content_hash(notebook.content)
            )
            self._session.add(
                ContentRevision(
                    user_id=user_id,
                    resource_type="notebook",
                    resource_id=notebook.id,
                    revision=next_revision,
                    content_hash=next_hash,
                    content=notebook.content,
                    device_id=device_id,
                )
            )
            notebook.folder_id = None
            notebook.revision = next_revision
            notebook.content_hash = next_hash
            await self._session.flush()
            await self._changes.append_upsert(
                user_id=user_id,
                resource_type="notebook",
                resource_id=notebook.id,
                payload=notebook_snapshot(notebook),
                revision=notebook.revision,
                content_hash=notebook.content_hash,
                device_id=device_id,
            )

        deleted_revision = folder.revision + 1
        deleted_hash = folder.content_hash
        await self._changes.append_delete(
            user_id=user_id,
            resource_type="folder",
            resource_id=folder.id,
            revision=deleted_revision,
            content_hash=deleted_hash,
            device_id=device_id,
        )
        await self._session.delete(folder)
        await self._session.flush()
        return ContentSaveResult(
            revision=deleted_revision,
            content_hash=deleted_hash,
            created_revision=True,
        )

    async def save_notebook_content(
        self,
        *,
        user_id: UUID,
        notebook_id: str,
        base_revision: int,
        content: dict[str, object],
        device_id: UUID | None = None,
    ) -> ContentSaveResult:
        return await self.save_notebook(
            user_id=user_id,
            notebook_id=notebook_id,
            base_revision=base_revision,
            content=content,
            device_id=device_id,
        )

    async def save_notebook(
        self,
        *,
        user_id: UUID,
        notebook_id: str,
        base_revision: int,
        content: dict[str, object] | None = None,
        metadata: dict[str, object] | None = None,
        base_metadata: dict[str, object] | None = None,
        device_id: UUID | None = None,
    ) -> ContentSaveResult:
        resource = await self._session.scalar(
            select(Notebook)
            .where(Notebook.id == notebook_id, Notebook.user_id == user_id)
            .with_for_update()
        )
        if resource is None:
            raise LibraryResourceNotFoundError("notebook", notebook_id)
        if device_id is not None:
            await self._ensure_active_device_owned(user_id=user_id, device_id=device_id)
        if resource.deleted_at is not None:
            raise ResourceDeletedError(current_revision=resource.revision)

        current_metadata: dict[str, object] = {
            "title": resource.title,
            "isArchived": resource.is_archived,
            "folderId": resource.folder_id,
        }
        merged_metadata = dict(current_metadata)
        if metadata is not None:
            if base_metadata is None:
                raise ValueError("base_metadata is required with metadata")
            conflicting_fields: list[str] = []
            for field in ("title", "isArchived", "folderId"):
                desired = metadata[field]
                baseline = base_metadata[field]
                current = current_metadata[field]
                if desired == baseline:
                    continue
                if current not in {baseline, desired}:
                    conflicting_fields.append(field)
                else:
                    merged_metadata[field] = desired
            if conflicting_fields:
                raise NotebookMetadataConflictError(conflicting_fields)
            folder_id = merged_metadata["folderId"]
            if folder_id is not None:
                folder = await self._session.scalar(
                    select(Folder).where(
                        Folder.id == folder_id, Folder.user_id == user_id
                    )
                )
                if folder is None:
                    raise LibraryResourceNotFoundError("folder", str(folder_id))

        normalized_content = (
            normalized_json_object(content) if content is not None else resource.content
        )
        new_hash = calculate_content_hash(normalized_content)
        content_changed = resource.content_hash != new_hash
        metadata_changed = merged_metadata != current_metadata
        if content_changed and resource.revision != base_revision:
            raise RevisionConflictError(
                expected_revision=base_revision,
                current_revision=resource.revision,
            )
        if not content_changed and not metadata_changed:
            return ContentSaveResult(
                revision=resource.revision,
                content_hash=resource.content_hash,
                created_revision=False,
            )

        next_revision = resource.revision + 1
        self._session.add(
            ContentRevision(
                user_id=user_id,
                resource_type="notebook",
                resource_id=resource.id,
                revision=next_revision,
                content_hash=new_hash,
                content=normalized_content,
                device_id=device_id,
            )
        )
        resource.revision = next_revision
        resource.content_hash = new_hash
        resource.content = normalized_content
        resource.title = str(merged_metadata["title"])
        resource.is_archived = bool(merged_metadata["isArchived"])
        resource.folder_id = (
            str(merged_metadata["folderId"])
            if merged_metadata["folderId"] is not None
            else None
        )
        await self._session.flush()
        await self._changes.append_upsert(
            user_id=user_id,
            resource_type="notebook",
            resource_id=resource.id,
            payload=notebook_snapshot(resource),
            revision=next_revision,
            content_hash=new_hash,
            device_id=device_id,
        )
        return ContentSaveResult(
            revision=next_revision,
            content_hash=new_hash,
            created_revision=True,
        )

    async def save_page_content(
        self,
        *,
        user_id: UUID,
        page_id: str,
        base_revision: int,
        content: dict[str, object],
        device_id: UUID | None = None,
    ) -> ContentSaveResult:
        resource = await self._session.scalar(
            select(Page)
            .where(Page.id == page_id, Page.user_id == user_id)
            .with_for_update()
        )
        if resource is None:
            raise LibraryResourceNotFoundError("page", page_id)
        return await self._save(
            resource=resource,
            resource_type="page",
            user_id=user_id,
            base_revision=base_revision,
            content=content,
            device_id=device_id,
        )

    async def save_infinite_canvas_content(
        self,
        *,
        user_id: UUID,
        canvas_id: str,
        base_revision: int,
        content: dict[str, object],
        device_id: UUID | None = None,
    ) -> ContentSaveResult:
        resource = await self._session.scalar(
            select(InfiniteCanvas)
            .where(
                InfiniteCanvas.id == canvas_id,
                InfiniteCanvas.user_id == user_id,
            )
            .with_for_update()
        )
        if resource is None:
            raise LibraryResourceNotFoundError("infinite canvas", canvas_id)
        return await self._save(
            resource=resource,
            resource_type="infinite_canvas",
            user_id=user_id,
            base_revision=base_revision,
            content=content,
            device_id=device_id,
        )

    async def list_revisions(
        self,
        *,
        user_id: UUID,
        resource_type: ResourceType,
        resource_id: str,
    ) -> list[ContentRevision]:
        await self._ensure_resource_owned(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
        )
        revisions = await self._session.scalars(
            select(ContentRevision)
            .where(
                ContentRevision.user_id == user_id,
                ContentRevision.resource_type == resource_type,
                ContentRevision.resource_id == resource_id,
            )
            .order_by(ContentRevision.revision.desc())
        )
        return list(revisions)

    async def _save(
        self,
        *,
        resource: RevisionedResource,
        resource_type: ResourceType,
        user_id: UUID,
        base_revision: int,
        content: dict[str, object],
        device_id: UUID | None,
    ) -> ContentSaveResult:
        if base_revision < 0:
            raise ValueError("base_revision must be non-negative")
        if device_id is not None:
            await self._ensure_active_device_owned(user_id=user_id, device_id=device_id)
        if resource.deleted_at is not None:
            raise ResourceDeletedError(current_revision=resource.revision)

        normalized_content = normalized_json_object(content)
        new_hash = calculate_content_hash(normalized_content)
        if resource.revision > 0 and resource.content_hash == new_hash:
            return ContentSaveResult(
                revision=resource.revision,
                content_hash=resource.content_hash,
                created_revision=False,
            )
        if resource.revision != base_revision:
            raise RevisionConflictError(
                expected_revision=base_revision,
                current_revision=resource.revision,
            )

        next_revision = resource.revision + 1
        revision = ContentRevision(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource.id,
            revision=next_revision,
            content_hash=new_hash,
            content=normalized_content,
            device_id=device_id,
        )
        resource.revision = next_revision
        resource.content_hash = new_hash
        resource.content = normalized_content
        self._session.add(revision)
        await self._session.flush()
        if isinstance(resource, Notebook):
            payload = notebook_snapshot(resource)
        elif isinstance(resource, Page):
            payload = page_snapshot(resource)
        else:
            payload = infinite_canvas_snapshot(resource)
        await self._changes.append_upsert(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource.id,
            payload=payload,
            revision=next_revision,
            content_hash=new_hash,
            device_id=device_id,
        )
        return ContentSaveResult(
            revision=next_revision,
            content_hash=new_hash,
            created_revision=True,
        )

    async def _ensure_active_device_owned(
        self, *, user_id: UUID, device_id: UUID
    ) -> None:
        device = await self._session.scalar(
            select(Device).where(
                Device.id == device_id,
                Device.user_id == user_id,
                Device.revoked_at.is_(None),
            )
        )
        if device is None:
            raise LibraryResourceNotFoundError("active device", str(device_id))

    async def _ensure_resource_owned(
        self,
        *,
        user_id: UUID,
        resource_type: ResourceType,
        resource_id: str,
    ) -> None:
        if resource_type == "notebook":
            resource = await self._session.scalar(
                select(Notebook).where(
                    Notebook.id == resource_id, Notebook.user_id == user_id
                )
            )
        elif resource_type == "page":
            resource = await self._session.scalar(
                select(Page).where(Page.id == resource_id, Page.user_id == user_id)
            )
        else:
            resource = await self._session.scalar(
                select(InfiniteCanvas).where(
                    InfiniteCanvas.id == resource_id,
                    InfiniteCanvas.user_id == user_id,
                )
            )
        if resource is None:
            raise LibraryResourceNotFoundError(resource_type, resource_id)
