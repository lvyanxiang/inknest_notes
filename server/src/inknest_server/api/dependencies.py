from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Annotated, cast

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.assets import AssetUploadService
from inknest_server.auth import LoginRateLimiter, PasswordManager, TokenManager
from inknest_server.auth.service import AuthService
from inknest_server.auth.tokens import InvalidAccessTokenError
from inknest_server.config import Settings
from inknest_server.db import Database
from inknest_server.errors import ApiError
from inknest_server.models import Device, User
from inknest_server.repositories.sync import SyncChangeRepository
from inknest_server.storage import ObjectStorage
from inknest_server.sync import SyncCursorCodec, SyncService

bearer_scheme = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class CurrentSession:
    user: User
    device: Device


async def get_db_session(request: Request) -> AsyncIterator[AsyncSession]:
    database = cast(Database, request.app.state.database)
    async with database.session() as session:
        yield session


DbSession = Annotated[AsyncSession, Depends(get_db_session)]


def get_auth_service(request: Request, session: DbSession) -> AuthService:
    return AuthService(
        session,
        cast(PasswordManager, request.app.state.password_manager),
        cast(TokenManager, request.app.state.token_manager),
        cast(LoginRateLimiter, request.app.state.login_rate_limiter),
    )


AuthServiceDependency = Annotated[AuthService, Depends(get_auth_service)]


def get_asset_upload_service(
    request: Request, session: DbSession
) -> AssetUploadService:
    return AssetUploadService(
        session,
        cast(ObjectStorage, request.app.state.object_storage),
        cast(Settings, request.app.state.settings),
    )


AssetUploadServiceDependency = Annotated[
    AssetUploadService, Depends(get_asset_upload_service)
]


def get_sync_service(request: Request, session: DbSession) -> SyncService:
    return SyncService(
        SyncChangeRepository(session),
        SyncCursorCodec(cast(Settings, request.app.state.settings)),
    )


SyncServiceDependency = Annotated[SyncService, Depends(get_sync_service)]


async def get_current_session(
    request: Request,
    session: DbSession,
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme),
    ],
) -> CurrentSession:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _authentication_required()

    token_manager = cast(TokenManager, request.app.state.token_manager)
    try:
        claims = token_manager.decode_access_token(credentials.credentials)
    except InvalidAccessTokenError as error:
        raise _authentication_required() from error

    result = await session.execute(
        select(User, Device)
        .join(Device, Device.user_id == User.id)
        .where(
            User.id == claims.user_id,
            User.is_active.is_(True),
            Device.id == claims.device_id,
            Device.revoked_at.is_(None),
        )
    )
    row = result.one_or_none()
    if row is None:
        raise _authentication_required()
    return CurrentSession(user=row[0], device=row[1])


CurrentSessionDependency = Annotated[CurrentSession, Depends(get_current_session)]


def _authentication_required() -> ApiError:
    return ApiError(
        code="authentication_required",
        message="A valid access token is required.",
        status_code=401,
    )
