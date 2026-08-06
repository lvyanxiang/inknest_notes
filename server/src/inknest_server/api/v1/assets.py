from uuid import UUID

from fastapi import APIRouter, Response, status

from inknest_server.api.dependencies import (
    AssetUploadServiceDependency,
    CurrentSessionDependency,
)
from inknest_server.assets import (
    AssetResponse,
    AssetUploadSessionResponse,
    CreateAssetUploadRequest,
)

router = APIRouter(prefix="/assets", tags=["assets"])


@router.post(
    "/upload-sessions",
    response_model=AssetUploadSessionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_asset_upload_session(
    payload: CreateAssetUploadRequest,
    current: CurrentSessionDependency,
    service: AssetUploadServiceDependency,
) -> AssetUploadSessionResponse:
    result = await service.create_upload_session(
        user_id=current.user.id,
        device_id=current.device.id,
        notebook_id=payload.notebook_id,
        asset_id=payload.asset_id,
        kind=payload.kind,
        filename=payload.filename,
        content_type=payload.content_type,
        byte_size=payload.byte_size,
        sha256=payload.sha256,
    )
    upload = result.upload
    return AssetUploadSessionResponse(
        upload_id=upload.id,
        asset_id=upload.asset_id,
        status=upload.status,
        object_key=upload.staging_object_key,
        upload_url=result.upload_url,
        required_headers={"Content-Type": upload.content_type},
        upload_url_expires_at=upload.upload_url_expires_at,
        session_expires_at=upload.expires_at,
    )


@router.post(
    "/upload-sessions/{upload_id}/complete",
    response_model=AssetResponse,
)
async def complete_asset_upload_session(
    upload_id: UUID,
    current: CurrentSessionDependency,
    service: AssetUploadServiceDependency,
) -> AssetResponse:
    asset = await service.complete_upload_session(
        user_id=current.user.id,
        upload_id=upload_id,
    )
    return AssetResponse(
        asset_id=asset.id,
        notebook_id=asset.notebook_id,
        kind=asset.kind,
        filename=asset.original_filename,
        content_type=asset.content_type,
        byte_size=asset.byte_size,
        sha256=asset.sha256,
        created_at=asset.created_at,
    )


@router.delete(
    "/upload-sessions/{upload_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def cancel_asset_upload_session(
    upload_id: UUID,
    current: CurrentSessionDependency,
    service: AssetUploadServiceDependency,
) -> Response:
    await service.cancel_upload_session(
        user_id=current.user.id,
        upload_id=upload_id,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
