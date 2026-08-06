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
    InfiniteCanvas,
    Notebook,
    Page,
)
from inknest_server.repositories.library import LibraryResourceNotFoundError
from inknest_server.repositories.sync import SyncChangeRepository
from inknest_server.sync.snapshots import (
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

    async def save_notebook_content(
        self,
        *,
        user_id: UUID,
        notebook_id: str,
        base_revision: int,
        content: dict[str, object],
        device_id: UUID | None = None,
    ) -> ContentSaveResult:
        resource = await self._session.scalar(
            select(Notebook)
            .where(Notebook.id == notebook_id, Notebook.user_id == user_id)
            .with_for_update()
        )
        if resource is None:
            raise LibraryResourceNotFoundError("notebook", notebook_id)
        return await self._save(
            resource=resource,
            resource_type="notebook",
            user_id=user_id,
            base_revision=base_revision,
            content=content,
            device_id=device_id,
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
