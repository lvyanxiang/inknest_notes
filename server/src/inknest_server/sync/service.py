from dataclasses import dataclass
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.content.canonical_json import content_hash
from inknest_server.models import SyncChange
from inknest_server.repositories.content import (
    ContentRepository,
    ResourceDeletedError,
    RevisionConflictError,
)
from inknest_server.repositories.library import LibraryResourceNotFoundError
from inknest_server.repositories.sync import (
    SyncChangeRepository,
    SyncCommitRepository,
)
from inknest_server.sync.conflicts import ConflictResolution, ConflictService
from inknest_server.sync.cursor import SyncCursorCodec
from inknest_server.sync.schemas import (
    SyncCommitOperation,
    SyncCommitOperationResult,
    SyncCommitRequest,
    SyncCommitResponse,
    SyncConflictResponse,
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
        cause: RevisionConflictError | LibraryResourceNotFoundError,
    ) -> None:
        self.operation = operation
        self.cause = cause
        super().__init__(f"synchronization operation failed: {operation.operation_id}")


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
        self._commits = SyncCommitRepository(session)
        self._conflicts = ConflictService(session)
        self._tombstones = TombstoneService(session)

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

        if operation.content is None:
            raise RuntimeError("validated upsert operation has no content")
        try:
            if operation.resource_type == "notebook":
                content_result = await self._content.save_notebook_content(
                    user_id=user_id,
                    notebook_id=operation.resource_id,
                    base_revision=operation.base_revision,
                    content=operation.content,
                    device_id=device_id,
                )
            elif operation.resource_type == "page":
                content_result = await self._content.save_page_content(
                    user_id=user_id,
                    page_id=operation.resource_id,
                    base_revision=operation.base_revision,
                    content=operation.content,
                    device_id=device_id,
                )
            else:
                content_result = await self._content.save_infinite_canvas_content(
                    user_id=user_id,
                    canvas_id=operation.resource_id,
                    base_revision=operation.base_revision,
                    content=operation.content,
                    device_id=device_id,
                )
        except ResourceDeletedError:
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
        except LibraryResourceNotFoundError as error:
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
