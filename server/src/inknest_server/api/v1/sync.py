from typing import Annotated

from fastapi import APIRouter, Query

from inknest_server.api.dependencies import (
    CurrentSessionDependency,
    SyncServiceDependency,
)
from inknest_server.errors import ApiError
from inknest_server.sync import (
    InvalidSyncCursorError,
    SyncChangeResponse,
    SyncChangesResponse,
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
