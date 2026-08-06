from datetime import UTC, datetime
from typing import Literal
from uuid import UUID, uuid4

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.content.canonical_json import (
    content_hash as calculate_content_hash,
)
from inknest_server.content.canonical_json import normalized_json_object
from inknest_server.models import Conflict, ContentRevision, Notebook, Page
from inknest_server.repositories.content import (
    ContentRepository,
    ResourceDeletedError,
    RevisionConflictError,
)
from inknest_server.repositories.library import LibraryResourceNotFoundError
from inknest_server.repositories.sync import SyncChangeRepository
from inknest_server.sync.snapshots import (
    conflict_snapshot,
    notebook_snapshot,
    page_snapshot,
)

ConflictResourceType = Literal["notebook", "page"]
ConflictResolution = Literal["keep_original", "use_conflict", "keep_both"]


class SyncConflictNotFoundError(Exception):
    pass


class SyncConflictAlreadyResolvedError(Exception):
    def __init__(self, resolution: str) -> None:
        self.resolution = resolution
        super().__init__("the synchronization conflict is already resolved")


class SyncConflictResolutionStaleError(Exception):
    def __init__(self, *, expected_revision: int, current_revision: int) -> None:
        self.expected_revision = expected_revision
        self.current_revision = current_revision
        super().__init__("the original resource changed after conflict creation")


class ConflictService:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._changes = SyncChangeRepository(session)
        self._content = ContentRepository(session)

    async def create(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        resource_type: ConflictResourceType,
        resource_id: str,
        base_revision: int,
        submitted_content: dict[str, object],
    ) -> Conflict:
        normalized_content = normalized_json_object(submitted_content)
        submitted_hash = calculate_content_hash(normalized_content)
        resource = await self._locked_resource(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
        )
        if resource.content_hash == submitted_hash:
            raise ValueError("identical content does not require a conflict copy")

        conflict = Conflict(
            user_id=user_id,
            resource_type=resource_type,
            original_resource_id=resource.id,
            copy_resource_id=str(uuid4()),
            copy_display_name=self._copy_display_name(resource),
            base_revision=base_revision,
            current_revision=resource.revision,
            submitted_content_hash=submitted_hash,
            submitted_content=normalized_content,
            current_content_hash=resource.content_hash,
            current_content=resource.content,
            source_device_id=device_id,
        )
        self._session.add(conflict)
        await self._session.flush()
        await self._append_change(conflict, device_id=device_id)
        return conflict

    async def resolve(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        conflict_id: UUID,
        resolution: ConflictResolution,
    ) -> Conflict:
        conflict = await self._session.scalar(
            select(Conflict)
            .where(Conflict.id == conflict_id, Conflict.user_id == user_id)
            .with_for_update()
        )
        if conflict is None:
            raise SyncConflictNotFoundError
        if conflict.status == "resolved":
            if conflict.resolution == resolution:
                return conflict
            raise SyncConflictAlreadyResolvedError(conflict.resolution or "unknown")

        if resolution == "use_conflict":
            await self._replace_original(conflict, user_id=user_id, device_id=device_id)
        elif resolution == "keep_both":
            await self._materialize_copy(
                conflict,
                user_id=user_id,
                device_id=device_id,
            )

        conflict.status = "resolved"
        conflict.resolution = resolution
        conflict.resolved_by_device_id = device_id
        conflict.resolved_at = datetime.now(UTC)
        await self._session.flush()
        await self._append_change(conflict, device_id=device_id)
        await self._session.commit()
        return conflict

    async def _replace_original(
        self,
        conflict: Conflict,
        *,
        user_id: UUID,
        device_id: UUID,
    ) -> None:
        try:
            if conflict.resource_type == "notebook":
                await self._content.save_notebook_content(
                    user_id=user_id,
                    notebook_id=conflict.original_resource_id,
                    base_revision=conflict.current_revision,
                    content=conflict.submitted_content,
                    device_id=device_id,
                )
            else:
                await self._content.save_page_content(
                    user_id=user_id,
                    page_id=conflict.original_resource_id,
                    base_revision=conflict.current_revision,
                    content=conflict.submitted_content,
                    device_id=device_id,
                )
        except (RevisionConflictError, ResourceDeletedError) as error:
            raise SyncConflictResolutionStaleError(
                expected_revision=conflict.current_revision,
                current_revision=error.current_revision,
            ) from error

    async def _materialize_copy(
        self,
        conflict: Conflict,
        *,
        user_id: UUID,
        device_id: UUID,
    ) -> None:
        resource_type: ConflictResourceType = (
            "notebook" if conflict.resource_type == "notebook" else "page"
        )
        resource = await self._locked_resource(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=conflict.original_resource_id,
        )
        if isinstance(resource, Notebook):
            notebook_copy = Notebook(
                id=conflict.copy_resource_id,
                user_id=user_id,
                folder_id=resource.folder_id,
                title=self._notebook_copy_title(resource.title),
                layout_mode=resource.layout_mode,
                is_archived=resource.is_archived,
                revision=1,
                content_hash=conflict.submitted_content_hash,
                content=conflict.submitted_content,
                conflict_of=resource.id,
            )
            self._session.add(notebook_copy)
            copy_resource_id = notebook_copy.id
            copy_snapshot = notebook_snapshot(notebook_copy)
        else:
            await self._session.scalar(
                select(Notebook)
                .where(
                    Notebook.id == resource.notebook_id,
                    Notebook.user_id == user_id,
                )
                .with_for_update()
            )
            max_position = await self._session.scalar(
                select(func.max(Page.position)).where(
                    Page.user_id == user_id,
                    Page.notebook_id == resource.notebook_id,
                )
            )
            page_copy = Page(
                id=conflict.copy_resource_id,
                user_id=user_id,
                notebook_id=resource.notebook_id,
                position=(max_position if max_position is not None else -1) + 1,
                width=resource.width,
                height=resource.height,
                coordinate_space_version=resource.coordinate_space_version,
                rotation_quarter_turns=resource.rotation_quarter_turns,
                template=resource.template,
                revision=1,
                content_hash=conflict.submitted_content_hash,
                content=conflict.submitted_content,
                conflict_of=resource.id,
            )
            self._session.add(page_copy)
            copy_resource_id = page_copy.id
            copy_snapshot = page_snapshot(page_copy)

        self._session.add(
            ContentRevision(
                user_id=user_id,
                resource_type=resource_type,
                resource_id=copy_resource_id,
                revision=1,
                content_hash=conflict.submitted_content_hash,
                content=conflict.submitted_content,
                device_id=device_id,
            )
        )
        await self._session.flush()
        await self._changes.append_upsert(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=copy_resource_id,
            payload=copy_snapshot,
            revision=1,
            content_hash=conflict.submitted_content_hash,
            device_id=device_id,
        )

    async def _locked_resource(
        self,
        *,
        user_id: UUID,
        resource_type: ConflictResourceType,
        resource_id: str,
    ) -> Notebook | Page:
        if resource_type == "notebook":
            resource = await self._session.scalar(
                select(Notebook)
                .where(Notebook.id == resource_id, Notebook.user_id == user_id)
                .with_for_update()
            )
        else:
            resource = await self._session.scalar(
                select(Page)
                .where(Page.id == resource_id, Page.user_id == user_id)
                .with_for_update()
            )
        if resource is None:
            raise LibraryResourceNotFoundError(resource_type, resource_id)
        return resource

    async def _append_change(self, conflict: Conflict, *, device_id: UUID) -> None:
        await self._changes.append_upsert(
            user_id=conflict.user_id,
            resource_type="conflict",
            resource_id=str(conflict.id),
            payload=conflict_snapshot(conflict),
            device_id=device_id,
        )

    @classmethod
    def _copy_display_name(cls, resource: Notebook | Page) -> str:
        if isinstance(resource, Notebook):
            return cls._notebook_copy_title(resource.title)
        return f"第 {resource.position + 1} 页（冲突副本）"

    @staticmethod
    def _notebook_copy_title(title: str) -> str:
        suffix = "（冲突副本）"
        return f"{title[: 300 - len(suffix)]}{suffix}"
