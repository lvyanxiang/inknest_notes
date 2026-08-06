from dataclasses import dataclass
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.content.canonical_json import content_hash
from inknest_server.models import SyncChange
from inknest_server.repositories.content import ContentRepository, RevisionConflictError
from inknest_server.repositories.library import LibraryResourceNotFoundError
from inknest_server.repositories.sync import (
    SyncChangeRepository,
    SyncCommitRepository,
)
from inknest_server.sync.cursor import SyncCursorCodec
from inknest_server.sync.schemas import (
    SyncCommitOperation,
    SyncCommitOperationResult,
    SyncCommitRequest,
    SyncCommitResponse,
)


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
        try:
            if operation.resource_type == "notebook":
                result = await self._content.save_notebook_content(
                    user_id=user_id,
                    notebook_id=operation.resource_id,
                    base_revision=operation.base_revision,
                    content=operation.content,
                    device_id=device_id,
                )
            elif operation.resource_type == "page":
                result = await self._content.save_page_content(
                    user_id=user_id,
                    page_id=operation.resource_id,
                    base_revision=operation.base_revision,
                    content=operation.content,
                    device_id=device_id,
                )
            else:
                result = await self._content.save_infinite_canvas_content(
                    user_id=user_id,
                    canvas_id=operation.resource_id,
                    base_revision=operation.base_revision,
                    content=operation.content,
                    device_id=device_id,
                )
        except (RevisionConflictError, LibraryResourceNotFoundError) as error:
            raise SyncOperationFailedError(operation, error) from error
        return SyncCommitOperationResult(
            operation_id=operation.operation_id,
            resource_type=operation.resource_type,
            resource_id=operation.resource_id,
            revision=result.revision,
            content_hash=result.content_hash,
            changed=result.created_revision,
        )
