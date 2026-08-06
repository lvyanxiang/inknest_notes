from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Literal, cast
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.content.canonical_json import (
    content_hash as calculate_content_hash,
)
from inknest_server.content.canonical_json import normalized_json_object
from inknest_server.models import (
    ContentRevision,
    InfiniteCanvas,
    Notebook,
    Page,
    Tombstone,
)
from inknest_server.repositories.library import LibraryResourceNotFoundError
from inknest_server.repositories.sync import SyncChangeRepository
from inknest_server.sync.snapshots import (
    infinite_canvas_snapshot,
    notebook_snapshot,
    page_snapshot,
    tombstone_snapshot,
)

TombstoneResourceType = Literal["notebook", "page", "infinite_canvas"]
RevisionedResource = Notebook | Page | InfiniteCanvas
TombstoneOutcome = Literal["deleted", "delete_conflict"]


class SyncTombstoneNotFoundError(Exception):
    pass


class SyncTombstoneStateError(Exception):
    def __init__(self, state: str) -> None:
        self.state = state
        super().__init__(f"tombstone cannot be restored from state {state}")


@dataclass(frozen=True, slots=True)
class TombstoneMutation:
    tombstone: Tombstone
    revision: int
    content_hash: str
    changed: bool
    outcome: TombstoneOutcome


class TombstoneService:
    """Soft-delete revisioned resources without losing concurrent edits."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._changes = SyncChangeRepository(session)

    async def delete(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        resource_type: TombstoneResourceType,
        resource_id: str,
        base_revision: int,
    ) -> TombstoneMutation:
        resource = await self._locked_resource(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
        )
        active = await self._active_tombstone(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
        )
        if resource.deleted_at is not None:
            if active is None:
                raise RuntimeError("soft-deleted resource has no active tombstone")
            return TombstoneMutation(
                tombstone=active,
                revision=resource.revision,
                content_hash=resource.content_hash,
                changed=False,
                outcome="deleted",
            )

        normalized_content = normalized_json_object(resource.content)
        current_hash = calculate_content_hash(normalized_content)
        if resource.revision != base_revision:
            tombstone = Tombstone(
                user_id=user_id,
                resource_type=resource_type,
                resource_id=resource_id,
                base_revision=base_revision,
                resource_revision=resource.revision,
                deleted_revision=None,
                content_hash=current_hash,
                content=normalized_content,
                deleted_by_device_id=device_id,
                deleted_at=datetime.now(UTC),
                state="restored",
                conflict_kind="delete_after_edit",
                resolution="preserved_edit",
                conflicting_device_id=device_id,
                restored_by_device_id=device_id,
                restored_at=datetime.now(UTC),
            )
            self._session.add(tombstone)
            await self._session.flush()
            await self._append_tombstone_change(tombstone, device_id=device_id)
            return TombstoneMutation(
                tombstone=tombstone,
                revision=resource.revision,
                content_hash=current_hash,
                changed=False,
                outcome="delete_conflict",
            )

        deleted_at = datetime.now(UTC)
        next_revision = resource.revision + 1
        resource.revision = next_revision
        resource.content = normalized_content
        resource.content_hash = current_hash
        resource.deleted_at = deleted_at
        await self._append_revision(
            user_id=user_id,
            device_id=device_id,
            resource_type=resource_type,
            resource_id=resource_id,
            revision=next_revision,
            content_hash=current_hash,
            content=normalized_content,
        )
        tombstone = Tombstone(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
            base_revision=base_revision,
            resource_revision=base_revision,
            deleted_revision=next_revision,
            content_hash=current_hash,
            content=normalized_content,
            deleted_by_device_id=device_id,
            deleted_at=deleted_at,
            state="active",
        )
        self._session.add(tombstone)
        await self._session.flush()
        await self._changes.append_delete(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
            revision=next_revision,
            content_hash=current_hash,
            device_id=device_id,
        )
        await self._append_tombstone_change(tombstone, device_id=device_id)
        return TombstoneMutation(
            tombstone=tombstone,
            revision=next_revision,
            content_hash=current_hash,
            changed=True,
            outcome="deleted",
        )

    async def preserve_edit_after_delete(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        resource_type: TombstoneResourceType,
        resource_id: str,
        content: dict[str, object],
    ) -> TombstoneMutation:
        resource = await self._locked_resource(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
        )
        tombstone = await self._active_tombstone(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
        )
        if resource.deleted_at is None or tombstone is None:
            raise RuntimeError("deleted-resource conflict state changed")

        normalized_content = normalized_json_object(content)
        new_hash = calculate_content_hash(normalized_content)
        if new_hash == resource.content_hash:
            return TombstoneMutation(
                tombstone=tombstone,
                revision=resource.revision,
                content_hash=resource.content_hash,
                changed=False,
                outcome="deleted",
            )

        next_revision = resource.revision + 1
        resource.revision = next_revision
        resource.content_hash = new_hash
        resource.content = normalized_content
        resource.deleted_at = None
        await self._append_revision(
            user_id=user_id,
            device_id=device_id,
            resource_type=resource_type,
            resource_id=resource_id,
            revision=next_revision,
            content_hash=new_hash,
            content=normalized_content,
        )
        tombstone.state = "restored"
        tombstone.conflict_kind = "edit_after_delete"
        tombstone.resolution = "preserved_edit"
        tombstone.conflicting_device_id = device_id
        tombstone.restored_by_device_id = device_id
        tombstone.restored_at = datetime.now(UTC)
        await self._session.flush()
        await self._changes.append_upsert(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
            payload=self._resource_snapshot(resource),
            revision=next_revision,
            content_hash=new_hash,
            device_id=device_id,
        )
        await self._append_tombstone_change(tombstone, device_id=device_id)
        return TombstoneMutation(
            tombstone=tombstone,
            revision=next_revision,
            content_hash=new_hash,
            changed=True,
            outcome="delete_conflict",
        )

    async def restore(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        tombstone_id: UUID,
    ) -> Tombstone:
        tombstone = await self._session.scalar(
            select(Tombstone)
            .where(Tombstone.id == tombstone_id, Tombstone.user_id == user_id)
            .with_for_update()
        )
        if tombstone is None:
            raise SyncTombstoneNotFoundError
        if tombstone.state != "active":
            raise SyncTombstoneStateError(tombstone.state)
        resource_type = cast(TombstoneResourceType, tombstone.resource_type)
        resource = await self._locked_resource(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=tombstone.resource_id,
        )
        if resource.deleted_at is None:
            raise SyncTombstoneStateError(tombstone.state)

        next_revision = resource.revision + 1
        resource.revision = next_revision
        resource.content_hash = tombstone.content_hash
        resource.content = normalized_json_object(tombstone.content)
        resource.deleted_at = None
        await self._append_revision(
            user_id=user_id,
            device_id=device_id,
            resource_type=resource_type,
            resource_id=resource.id,
            revision=next_revision,
            content_hash=resource.content_hash,
            content=resource.content,
        )
        tombstone.state = "restored"
        tombstone.resolution = "restored_snapshot"
        tombstone.restored_by_device_id = device_id
        tombstone.restored_at = datetime.now(UTC)
        await self._session.flush()
        await self._changes.append_upsert(
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource.id,
            payload=self._resource_snapshot(resource),
            revision=next_revision,
            content_hash=resource.content_hash,
            device_id=device_id,
        )
        await self._append_tombstone_change(tombstone, device_id=device_id)
        return tombstone

    async def _locked_resource(
        self,
        *,
        user_id: UUID,
        resource_type: TombstoneResourceType,
        resource_id: str,
    ) -> RevisionedResource:
        model: type[Notebook] | type[Page] | type[InfiniteCanvas]
        label: str
        if resource_type == "notebook":
            model, label = Notebook, "notebook"
        elif resource_type == "page":
            model, label = Page, "page"
        else:
            model, label = InfiniteCanvas, "infinite canvas"
        resource = cast(
            RevisionedResource | None,
            await self._session.scalar(
                select(model)
                .where(model.id == resource_id, model.user_id == user_id)
                .with_for_update()
            ),
        )
        if resource is None:
            raise LibraryResourceNotFoundError(label, resource_id)
        return resource

    async def _active_tombstone(
        self,
        *,
        user_id: UUID,
        resource_type: TombstoneResourceType,
        resource_id: str,
    ) -> Tombstone | None:
        return cast(
            Tombstone | None,
            await self._session.scalar(
                select(Tombstone)
                .where(
                    Tombstone.user_id == user_id,
                    Tombstone.resource_type == resource_type,
                    Tombstone.resource_id == resource_id,
                    Tombstone.state == "active",
                )
                .with_for_update()
            ),
        )

    async def _append_revision(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        resource_type: TombstoneResourceType,
        resource_id: str,
        revision: int,
        content_hash: str,
        content: dict[str, object],
    ) -> None:
        self._session.add(
            ContentRevision(
                user_id=user_id,
                resource_type=resource_type,
                resource_id=resource_id,
                revision=revision,
                content_hash=content_hash,
                content=content,
                device_id=device_id,
            )
        )
        await self._session.flush()

    async def _append_tombstone_change(
        self, tombstone: Tombstone, *, device_id: UUID
    ) -> None:
        await self._changes.append_upsert(
            user_id=tombstone.user_id,
            resource_type="tombstone",
            resource_id=str(tombstone.id),
            payload=tombstone_snapshot(tombstone),
            device_id=device_id,
        )

    @staticmethod
    def _resource_snapshot(resource: RevisionedResource) -> dict[str, object]:
        if isinstance(resource, Notebook):
            return notebook_snapshot(resource)
        if isinstance(resource, Page):
            return page_snapshot(resource)
        return infinite_canvas_snapshot(resource)
