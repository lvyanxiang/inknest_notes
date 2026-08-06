from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Query

from inknest_server.api.dependencies import (
    CurrentSessionDependency,
    SyncServiceDependency,
)
from inknest_server.errors import ApiError
from inknest_server.repositories import RevisionConflictError
from inknest_server.repositories.sync import SyncIdempotencyKeyReusedError
from inknest_server.sync import (
    InvalidSyncCursorError,
    ResolveSyncConflictRequest,
    SyncChangeResponse,
    SyncChangesResponse,
    SyncCommitRequest,
    SyncCommitResponse,
    SyncConflictResponse,
    SyncTombstoneResponse,
)
from inknest_server.sync.conflicts import (
    SyncConflictAlreadyResolvedError,
    SyncConflictNotFoundError,
    SyncConflictResolutionStaleError,
)
from inknest_server.sync.service import (
    SyncCursorAheadError,
    SyncDeviceMismatchError,
    SyncOperationFailedError,
)
from inknest_server.sync.tombstones import (
    SyncTombstoneNotFoundError,
    SyncTombstoneStateError,
)

router = APIRouter(prefix="/sync", tags=["sync"])


@router.get("/changes", response_model=SyncChangesResponse)
async def list_sync_changes(
    current: CurrentSessionDependency,
    service: SyncServiceDependency,
    cursor: Annotated[str | None, Query(min_length=1, max_length=2048)] = None,
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
) -> SyncChangesResponse:
    try:
        result = await service.list_changes(
            user_id=current.user.id,
            cursor=cursor,
            limit=limit,
        )
    except InvalidSyncCursorError as error:
        raise ApiError(
            code="sync_cursor_invalid",
            message="The synchronization cursor is invalid for this account.",
            status_code=400,
        ) from error
    return SyncChangesResponse(
        changes=[
            SyncChangeResponse.model_validate(change) for change in result.changes
        ],
        next_cursor=result.next_cursor,
        has_more=result.has_more,
    )


@router.post("/commit", response_model=SyncCommitResponse)
async def commit_sync_changes(
    payload: SyncCommitRequest,
    current: CurrentSessionDependency,
    service: SyncServiceDependency,
) -> SyncCommitResponse:
    try:
        return await service.commit(
            user_id=current.user.id,
            authenticated_device_id=current.device.id,
            request=payload,
        )
    except InvalidSyncCursorError as error:
        raise ApiError(
            code="sync_cursor_invalid",
            message="The synchronization cursor is invalid for this account.",
            status_code=400,
        ) from error
    except SyncCursorAheadError as error:
        raise ApiError(
            code="sync_cursor_ahead",
            message="The synchronization cursor is ahead of the account state.",
            status_code=409,
        ) from error
    except SyncDeviceMismatchError as error:
        raise ApiError(
            code="sync_device_mismatch",
            message="The request device does not match the authenticated device.",
            status_code=403,
        ) from error
    except SyncIdempotencyKeyReusedError as error:
        raise ApiError(
            code="sync_idempotency_key_reused",
            message="The idempotency key was already used for another request.",
            status_code=409,
        ) from error
    except SyncOperationFailedError as error:
        operation = error.operation
        details: dict[str, Any] = {
            "operationId": operation.operation_id,
            "resourceType": operation.resource_type,
            "resourceId": operation.resource_id,
        }
        if isinstance(error.cause, RevisionConflictError):
            details.update(
                {
                    "expectedRevision": error.cause.expected_revision,
                    "currentRevision": error.cause.current_revision,
                }
            )
            raise ApiError(
                code="sync_revision_conflict",
                message="A resource changed after the submitted base revision.",
                status_code=409,
                details=details,
            ) from error
        raise ApiError(
            code="sync_resource_not_found",
            message=str(error.cause),
            status_code=404,
            details=details,
        ) from error


@router.post(
    "/conflicts/{conflict_id}/resolve",
    response_model=SyncConflictResponse,
)
async def resolve_sync_conflict(
    conflict_id: UUID,
    payload: ResolveSyncConflictRequest,
    current: CurrentSessionDependency,
    service: SyncServiceDependency,
) -> SyncConflictResponse:
    try:
        return await service.resolve_conflict(
            user_id=current.user.id,
            device_id=current.device.id,
            conflict_id=conflict_id,
            resolution=payload.resolution,
        )
    except SyncConflictNotFoundError as error:
        raise ApiError(
            code="sync_conflict_not_found",
            message="The synchronization conflict was not found.",
            status_code=404,
        ) from error
    except SyncConflictAlreadyResolvedError as error:
        raise ApiError(
            code="sync_conflict_already_resolved",
            message="The synchronization conflict was already resolved differently.",
            status_code=409,
            details={"currentResolution": error.resolution},
        ) from error
    except SyncConflictResolutionStaleError as error:
        raise ApiError(
            code="sync_conflict_resolution_stale",
            message="The original resource changed after this conflict was created.",
            status_code=409,
            details={
                "expectedRevision": error.expected_revision,
                "currentRevision": error.current_revision,
            },
        ) from error


@router.post(
    "/tombstones/{tombstone_id}/restore",
    response_model=SyncTombstoneResponse,
)
async def restore_sync_tombstone(
    tombstone_id: UUID,
    current: CurrentSessionDependency,
    service: SyncServiceDependency,
) -> SyncTombstoneResponse:
    try:
        return await service.restore_tombstone(
            user_id=current.user.id,
            device_id=current.device.id,
            tombstone_id=tombstone_id,
        )
    except SyncTombstoneNotFoundError as error:
        raise ApiError(
            code="sync_tombstone_not_found",
            message="The synchronization tombstone was not found.",
            status_code=404,
        ) from error
    except SyncTombstoneStateError as error:
        raise ApiError(
            code="sync_tombstone_not_active",
            message="Only an active tombstone can be restored.",
            status_code=409,
            details={"currentState": error.state},
        ) from error
