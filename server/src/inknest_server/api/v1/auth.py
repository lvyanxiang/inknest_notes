from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Request, Response, status

from inknest_server.api.dependencies import (
    AuthServiceDependency,
    CurrentSessionDependency,
)
from inknest_server.auth.agreements import (
    CURRENT_PRIVACY_POLICY_VERSION,
    CURRENT_TERMS_VERSION,
)
from inknest_server.auth.schemas import (
    AcceptAgreementsRequest,
    AccountDeletionResponse,
    AgreementVersionsResponse,
    ChangePasswordRequest,
    DeleteAccountRequest,
    DeviceResponse,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
)
from inknest_server.auth.service import AuthResult

router = APIRouter(tags=["authentication"])


@router.post(
    "/auth/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
)
async def register(
    payload: RegisterRequest,
    service: AuthServiceDependency,
) -> TokenResponse:
    result = await service.register(
        email=str(payload.email),
        password=payload.password,
        device_name=payload.device_name,
        platform=payload.platform,
        client_instance_id=payload.client_instance_id,
        privacy_policy_version=payload.privacy_policy_version,
        terms_version=payload.terms_version,
    )
    return _token_response(result, service)


@router.post("/auth/login", response_model=TokenResponse)
async def login(
    request: Request,
    payload: LoginRequest,
    service: AuthServiceDependency,
) -> TokenResponse:
    result = await service.login(
        email=str(payload.email),
        password=payload.password,
        device_name=payload.device_name,
        platform=payload.platform,
        client_instance_id=payload.client_instance_id,
        client_id=request.client.host if request.client is not None else "unknown",
    )
    return _token_response(result, service)


@router.post("/auth/refresh", response_model=TokenResponse)
async def refresh(
    payload: RefreshRequest,
    service: AuthServiceDependency,
) -> TokenResponse:
    result = await service.refresh(payload.refresh_token)
    return _token_response(result, service)


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    payload: LogoutRequest,
    service: AuthServiceDependency,
) -> Response:
    await service.logout(payload.refresh_token)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=UserResponse)
async def me(current: CurrentSessionDependency) -> UserResponse:
    return UserResponse.model_validate(current.user)


@router.get("/legal/agreements", response_model=AgreementVersionsResponse)
async def agreement_versions() -> AgreementVersionsResponse:
    return AgreementVersionsResponse(
        privacy_policy_version=CURRENT_PRIVACY_POLICY_VERSION,
        terms_version=CURRENT_TERMS_VERSION,
        effective_date="2026-08-31",
    )


@router.put("/me/agreements", response_model=UserResponse)
async def accept_agreements(
    payload: AcceptAgreementsRequest,
    current: CurrentSessionDependency,
    service: AuthServiceDependency,
) -> UserResponse:
    await service.accept_agreements(
        user=current.user,
        privacy_policy_version=payload.privacy_policy_version,
        terms_version=payload.terms_version,
    )
    return UserResponse.model_validate(current.user)


@router.put("/me/password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(
    payload: ChangePasswordRequest,
    current: CurrentSessionDependency,
    service: AuthServiceDependency,
) -> Response:
    await service.change_password(
        user=current.user,
        current_device_id=current.device.id,
        current_password=payload.current_password,
        new_password=payload.new_password,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete(
    "/me",
    response_model=AccountDeletionResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def delete_account(
    payload: DeleteAccountRequest,
    current: CurrentSessionDependency,
    service: AuthServiceDependency,
) -> AccountDeletionResponse:
    result = await service.request_account_deletion(
        user=current.user,
        password=payload.password,
    )
    deletion_status: Literal["pending", "completed"] = (
        "completed" if result.status == "completed" else "pending"
    )
    return AccountDeletionResponse(
        status=deletion_status,
        cloud_deletion_complete=result.status == "completed",
    )


@router.get("/devices", response_model=list[DeviceResponse])
async def list_devices(
    current: CurrentSessionDependency,
    service: AuthServiceDependency,
) -> list[DeviceResponse]:
    devices = await service.list_devices(current.user.id)
    return [
        DeviceResponse.model_validate(device).model_copy(
            update={"current": device.id == current.device.id}
        )
        for device in devices
    ]


@router.delete("/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_device(
    device_id: UUID,
    current: CurrentSessionDependency,
    service: AuthServiceDependency,
) -> Response:
    await service.revoke_device(user_id=current.user.id, device_id=device_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def _token_response(
    result: AuthResult, service: AuthServiceDependency
) -> TokenResponse:
    return TokenResponse(
        access_token=result.access_token,
        refresh_token=result.refresh_token,
        expires_in=service.access_token_seconds,
        user=UserResponse.model_validate(result.user),
        device=DeviceResponse.model_validate(result.device).model_copy(
            update={"current": True}
        ),
    )
