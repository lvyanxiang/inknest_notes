from dataclasses import dataclass
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.content.canonical_json import content_hash
from inknest_server.models import SyncChange
from inknest_server.repositories.content import (
    ContentRepository,
    FolderMetadataConflictError,
    NotebookMetadataConflictError,
    ResourceDeletedError,
    RevisionConflictError,
)
from inknest_server.repositories.library import LibraryResourceNotFoundError
from inknest_server.repositories.sync import (
    SyncChangeRepository,
    SyncCommitRepository,
)
from inknest_server.sync.bootstrap import SyncBootstrapRepository
from inknest_server.sync.conflicts import ConflictResolution, ConflictService
from inknest_server.sync.cursor import SyncCursorCodec
from inknest_server.sync.merge import (
    SyncMergeParentIncompatibleError,
    SyncMergeRepository,
    SyncMergeResourceExistsError,
)
from inknest_server.sync.schemas import (
    SyncBootstrapAsset,
    SyncBootstrapCounts,
    SyncBootstrapFolder,
    SyncBootstrapInfiniteCanvas,
    SyncBootstrapNotebook,
    SyncBootstrapPage,
    SyncBootstrapResponse,
    SyncCommitOperation,
    SyncCommitOperationResult,
    SyncCommitRequest,
    SyncCommitResponse,
    SyncConflictResponse,
    SyncFolderMetadata,
    SyncMergeCommitRequest,
    SyncMergeCommitResponse,
    SyncMergeCreateOperation,
    SyncMergeCreateOperationResult,
    SyncMergeFolderMetadata,
    SyncMergeInfiniteCanvasMetadata,
    SyncMergeNotebookMetadata,
    SyncMergePageMetadata,
    SyncTombstoneResponse,
)
from inknest_server.sync.tombstones import TombstoneService


class SyncDeviceMismatchError(Exception):
    pass


class SyncCursorAheadError(Exception):
    pass


class SyncOperationFailedError(Exception):
    def __init__(
        self,
        operation: SyncCommitOperation,
        cause: (
            RevisionConflictError
            | FolderMetadataConflictError
            | NotebookMetadataConflictError
            | ResourceDeletedError
            | LibraryResourceNotFoundError
        ),
    ) -> None:
        self.operation = operation
        self.cause = cause
        super().__init__(f"synchronization operation failed: {operation.operation_id}")


class SyncMergeOperationFailedError(Exception):
    def __init__(
        self,
        operation: SyncMergeCreateOperation,
        cause: (
            SyncMergeResourceExistsError
            | SyncMergeParentIncompatibleError
            | LibraryResourceNotFoundError
        ),
    ) -> None:
        self.operation = operation
        self.cause = cause
        super().__init__(f"merge creation failed: {operation.operation_id}")


@dataclass(frozen=True, slots=True)
class SyncChangePage:
    changes: list[SyncChange]
    next_cursor: str
    has_more: bool


class SyncService:
    def __init__(
        self,
        session: AsyncSession,
        repository: SyncChangeRepository,
        cursor_codec: SyncCursorCodec,
    ) -> None:
        self._session = session
        self._repository = repository
        self._cursor_codec = cursor_codec
        self._content = ContentRepository(session)
        self._bootstrap = SyncBootstrapRepository(session)
        self._commits = SyncCommitRepository(session)
        self._conflicts = ConflictService(session)
        self._merge = SyncMergeRepository(session)
        self._tombstones = TombstoneService(session)

    async def bootstrap(self, *, user_id: UUID) -> SyncBootstrapResponse:
        # Capture the cursor first. A concurrent write may then appear both in
        # this inventory and in the later incremental feed, but it cannot be
        # skipped by advancing the cursor past an unseen resource.
        base_sequence = await self._repository.latest_sequence(user_id=user_id)
        inventory = await self._bootstrap.read_inventory(user_id=user_id)
        return SyncBootstrapResponse(
            has_cloud_library=inventory.has_cloud_library,
            folder_ids=inventory.folder_ids,
            notebook_ids=inventory.notebook_ids,
            folders=[
                SyncBootstrapFolder.model_validate(folder)
                for folder in inventory.folders
            ],
            notebooks=[
                SyncBootstrapNotebook.model_validate(notebook)
                for notebook in inventory.notebooks
            ],
            pages=[SyncBootstrapPage.model_validate(page) for page in inventory.pages],
            infinite_canvases=[
                SyncBootstrapInfiniteCanvas.model_validate(canvas)
                for canvas in inventory.infinite_canvases
            ],
            assets=[
                SyncBootstrapAsset.model_validate(asset) for asset in inventory.assets
            ],
            counts=SyncBootstrapCounts(
                folders=len(inventory.folder_ids),
                notebooks=len(inventory.notebook_ids),
                pages=len(inventory.pages),
                infinite_canvases=len(inventory.infinite_canvases),
                assets=len(inventory.assets),
            ),
            base_cursor=self._cursor_codec.encode(
                user_id=user_id,
                sequence=base_sequence,
            ),
        )

    async def commit_merge_creates(
        self,
        *,
        user_id: UUID,
        authenticated_device_id: UUID,
        request: SyncMergeCommitRequest,
    ) -> SyncMergeCommitResponse:
        if request.device_id != authenticated_device_id:
            raise SyncDeviceMismatchError

        base_sequence = self._cursor_codec.decode(
            request.base_cursor,
            user_id=user_id,
        )
        latest_sequence = await self._repository.latest_sequence(user_id=user_id)
        if base_sequence > latest_sequence:
            raise SyncCursorAheadError

        request_hash = content_hash(request.model_dump(mode="json", by_alias=True))
        reservation = await self._commits.reserve(
            user_id=user_id,
            device_id=authenticated_device_id,
            idempotency_key=request.idempotency_key,
            request_hash=request_hash,
        )
        if reservation.replayed:
            return SyncMergeCommitResponse.model_validate(
                {**reservation.record.response_payload, "replayed": True}
            )

        try:
            ordered_operations = sorted(
                request.operations,
                key=lambda operation: {
                    "folder": 0,
                    "notebook": 1,
                    "page": 2,
                    "infinite_canvas": 2,
                }[operation.resource_type],
            )
            results_by_operation_id = {
                operation.operation_id: await self._apply_merge_create(
                    user_id=user_id,
                    device_id=authenticated_device_id,
                    operation=operation,
                )
                for operation in ordered_operations
            }
            latest_sequence = await self._repository.latest_sequence(user_id=user_id)
            response = SyncMergeCommitResponse(
                idempotency_key=request.idempotency_key,
                replayed=False,
                results=[
                    results_by_operation_id[operation.operation_id]
                    for operation in request.operations
                ],
                next_cursor=self._cursor_codec.encode(
                    user_id=user_id,
                    sequence=latest_sequence,
                ),
            )
            reservation.record.response_payload = response.model_dump(
                mode="json", by_alias=True
            )
            await self._session.commit()
            return response
        except Exception:
            await self._session.rollback()
            raise

    async def _apply_merge_create(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        operation: SyncMergeCreateOperation,
    ) -> SyncMergeCreateOperationResult:
        try:
            if operation.resource_type == "folder":
                if not isinstance(operation.metadata, SyncMergeFolderMetadata):
                    raise RuntimeError("validated folder metadata has wrong type")
                result = await self._merge.create_folder(
                    user_id=user_id,
                    device_id=device_id,
                    folder_id=operation.resource_id,
                    metadata=operation.metadata,
                )
            elif operation.resource_type == "notebook":
                if not isinstance(operation.metadata, SyncMergeNotebookMetadata):
                    raise RuntimeError("validated notebook metadata has wrong type")
                result = await self._merge.create_notebook(
                    user_id=user_id,
                    device_id=device_id,
                    notebook_id=operation.resource_id,
                    metadata=operation.metadata,
                )
            elif operation.resource_type == "page":
                if not isinstance(operation.metadata, SyncMergePageMetadata):
                    raise RuntimeError("validated page metadata has wrong type")
                result = await self._merge.create_page(
                    user_id=user_id,
                    device_id=device_id,
                    page_id=operation.resource_id,
                    metadata=operation.metadata,
                )
            else:
                if not isinstance(operation.metadata, SyncMergeInfiniteCanvasMetadata):
                    raise RuntimeError(
                        "validated infinite canvas metadata has wrong type"
                    )
                result = await self._merge.create_infinite_canvas(
                    user_id=user_id,
                    device_id=device_id,
                    canvas_id=operation.resource_id,
                    metadata=operation.metadata,
                )
        except (
            SyncMergeResourceExistsError,
            SyncMergeParentIncompatibleError,
            LibraryResourceNotFoundError,
        ) as error:
            raise SyncMergeOperationFailedError(operation, error) from error
        return SyncMergeCreateOperationResult(
            operation_id=operation.operation_id,
            resource_type=operation.resource_type,
            resource_id=operation.resource_id,
            outcome=result.outcome,
            revision=result.revision,
            content_hash=result.content_hash,
        )

    async def list_changes(
        self,
        *,
        user_id: UUID,
        cursor: str | None,
        limit: int,
    ) -> SyncChangePage:
        after_sequence = (
            self._cursor_codec.decode(cursor, user_id=user_id)
            if cursor is not None
            else 0
        )
        rows = await self._repository.list_after(
            user_id=user_id,
            after_sequence=after_sequence,
            limit=limit + 1,
        )
        has_more = len(rows) > limit
        changes = rows[:limit]
        next_sequence = changes[-1].sequence if changes else after_sequence
        return SyncChangePage(
            changes=changes,
            next_cursor=self._cursor_codec.encode(
                user_id=user_id,
                sequence=next_sequence,
            ),
            has_more=has_more,
        )

    async def commit(
        self,
        *,
        user_id: UUID,
        authenticated_device_id: UUID,
        request: SyncCommitRequest,
    ) -> SyncCommitResponse:
        if request.device_id != authenticated_device_id:
            raise SyncDeviceMismatchError

        base_sequence = self._cursor_codec.decode(
            request.base_cursor,
            user_id=user_id,
        )
        latest_sequence = await self._repository.latest_sequence(user_id=user_id)
        if base_sequence > latest_sequence:
            raise SyncCursorAheadError

        request_hash = content_hash(request.model_dump(mode="json", by_alias=True))
        reservation = await self._commits.reserve(
            user_id=user_id,
            device_id=authenticated_device_id,
            idempotency_key=request.idempotency_key,
            request_hash=request_hash,
        )
        if reservation.replayed:
            return SyncCommitResponse.model_validate(
                {**reservation.record.response_payload, "replayed": True}
            )

        try:
            results = [
                await self._apply_operation(
                    user_id=user_id,
                    device_id=authenticated_device_id,
                    operation=operation,
                )
                for operation in request.operations
            ]
            latest_sequence = await self._repository.latest_sequence(user_id=user_id)
            response = SyncCommitResponse(
                idempotency_key=request.idempotency_key,
                replayed=False,
                results=results,
                next_cursor=self._cursor_codec.encode(
                    user_id=user_id,
                    sequence=latest_sequence,
                ),
            )
            reservation.record.response_payload = response.model_dump(
                mode="json", by_alias=True
            )
            await self._session.commit()
            return response
        except Exception:
            await self._session.rollback()
            raise

    async def _apply_operation(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        operation: SyncCommitOperation,
    ) -> SyncCommitOperationResult:
        if operation.operation == "delete":
            if operation.resource_type == "folder":
                try:
                    folder_delete_result = await self._content.delete_folder(
                        user_id=user_id,
                        device_id=device_id,
                        folder_id=operation.resource_id,
                        base_revision=operation.base_revision,
                    )
                except (LibraryResourceNotFoundError, RevisionConflictError) as error:
                    raise SyncOperationFailedError(operation, error) from error
                return SyncCommitOperationResult(
                    operation_id=operation.operation_id,
                    resource_type=operation.resource_type,
                    resource_id=operation.resource_id,
                    revision=folder_delete_result.revision,
                    content_hash=folder_delete_result.content_hash,
                    changed=folder_delete_result.created_revision,
                    outcome="deleted",
                )
            try:
                delete_result = await self._tombstones.delete(
                    user_id=user_id,
                    device_id=device_id,
                    resource_type=operation.resource_type,
                    resource_id=operation.resource_id,
                    base_revision=operation.base_revision,
                )
            except LibraryResourceNotFoundError as error:
                raise SyncOperationFailedError(operation, error) from error
            return SyncCommitOperationResult(
                operation_id=operation.operation_id,
                resource_type=operation.resource_type,
                resource_id=operation.resource_id,
                revision=delete_result.revision,
                content_hash=delete_result.content_hash,
                changed=delete_result.changed,
                outcome=delete_result.outcome,
                tombstone=SyncTombstoneResponse.model_validate(delete_result.tombstone),
            )

        try:
            if operation.resource_type == "folder":
                if not isinstance(operation.metadata, SyncFolderMetadata):
                    raise RuntimeError("validated folder upsert has wrong metadata")
                content_result = await self._content.save_folder(
                    user_id=user_id,
                    folder_id=operation.resource_id,
                    base_revision=operation.base_revision,
                    metadata=operation.metadata.model_dump(mode="json", by_alias=True),
                    base_metadata=(
                        operation.base_metadata.model_dump(mode="json", by_alias=True)
                        if operation.base_metadata is not None
                        else None
                    ),
                    device_id=device_id,
                )
            elif operation.resource_type == "notebook":
                content_result = await self._content.save_notebook(
                    user_id=user_id,
                    notebook_id=operation.resource_id,
                    base_revision=operation.base_revision,
                    content=operation.content,
                    metadata=(
                        operation.metadata.model_dump(mode="json", by_alias=True)
                        if operation.metadata is not None
                        else None
                    ),
                    base_metadata=(
                        operation.base_metadata.model_dump(mode="json", by_alias=True)
                        if operation.base_metadata is not None
                        else None
                    ),
                    device_id=device_id,
                )
            elif operation.resource_type == "page":
                if operation.content is None:
                    raise RuntimeError("validated page upsert has no content")
                content_result = await self._content.save_page_content(
                    user_id=user_id,
                    page_id=operation.resource_id,
                    base_revision=operation.base_revision,
                    content=operation.content,
                    device_id=device_id,
                )
            else:
                if operation.content is None:
                    raise RuntimeError("validated canvas upsert has no content")
                content_result = await self._content.save_infinite_canvas_content(
                    user_id=user_id,
                    canvas_id=operation.resource_id,
                    base_revision=operation.base_revision,
                    content=operation.content,
                    device_id=device_id,
                )
        except ResourceDeletedError as error:
            if operation.resource_type == "folder" or operation.content is None:
                raise SyncOperationFailedError(operation, error) from error
            tombstone_result = await self._tombstones.preserve_edit_after_delete(
                user_id=user_id,
                device_id=device_id,
                resource_type=operation.resource_type,
                resource_id=operation.resource_id,
                content=operation.content,
            )
            return SyncCommitOperationResult(
                operation_id=operation.operation_id,
                resource_type=operation.resource_type,
                resource_id=operation.resource_id,
                revision=tombstone_result.revision,
                content_hash=tombstone_result.content_hash,
                changed=tombstone_result.changed,
                outcome=tombstone_result.outcome,
                tombstone=SyncTombstoneResponse.model_validate(
                    tombstone_result.tombstone
                ),
            )
        except RevisionConflictError as error:
            if operation.resource_type in {"notebook", "page"}:
                if operation.content is None:
                    raise SyncOperationFailedError(operation, error) from error
                conflict = await self._conflicts.create(
                    user_id=user_id,
                    device_id=device_id,
                    resource_type=operation.resource_type,
                    resource_id=operation.resource_id,
                    base_revision=operation.base_revision,
                    submitted_content=operation.content,
                )
                return SyncCommitOperationResult(
                    operation_id=operation.operation_id,
                    resource_type=operation.resource_type,
                    resource_id=operation.resource_id,
                    revision=conflict.current_revision,
                    content_hash=conflict.current_content_hash,
                    changed=False,
                    outcome="conflict",
                    conflict=SyncConflictResponse.model_validate(conflict),
                )
            raise SyncOperationFailedError(operation, error) from error
        except (
            FolderMetadataConflictError,
            NotebookMetadataConflictError,
            LibraryResourceNotFoundError,
        ) as error:
            raise SyncOperationFailedError(operation, error) from error
        return SyncCommitOperationResult(
            operation_id=operation.operation_id,
            resource_type=operation.resource_type,
            resource_id=operation.resource_id,
            revision=content_result.revision,
            content_hash=content_result.content_hash,
            changed=content_result.created_revision,
            outcome="applied" if content_result.created_revision else "unchanged",
        )

    async def restore_tombstone(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        tombstone_id: UUID,
    ) -> SyncTombstoneResponse:
        try:
            tombstone = await self._tombstones.restore(
                user_id=user_id,
                device_id=device_id,
                tombstone_id=tombstone_id,
            )
            await self._session.commit()
        except Exception:
            await self._session.rollback()
            raise
        return SyncTombstoneResponse.model_validate(tombstone)

    async def resolve_conflict(
        self,
        *,
        user_id: UUID,
        device_id: UUID,
        conflict_id: UUID,
        resolution: ConflictResolution,
    ) -> SyncConflictResponse:
        try:
            conflict = await self._conflicts.resolve(
                user_id=user_id,
                device_id=device_id,
                conflict_id=conflict_id,
                resolution=resolution,
            )
        except Exception:
            await self._session.rollback()
            raise
        return SyncConflictResponse.model_validate(conflict)
