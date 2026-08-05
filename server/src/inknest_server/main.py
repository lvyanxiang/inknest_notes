from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from inknest_server.api.v1.router import router as api_v1_router
from inknest_server.auth import LoginRateLimiter, PasswordManager, TokenManager
from inknest_server.config import Settings, get_settings
from inknest_server.db import Database
from inknest_server.errors import register_error_handlers
from inknest_server.logging_config import configure_logging
from inknest_server.middleware.request_id import RequestIdMiddleware
from inknest_server.services.readiness import ReadinessChecker, ReadinessService
from inknest_server.storage import MinioStorage


def create_app(
    *,
    settings: Settings | None = None,
    readiness_checker: ReadinessChecker | None = None,
    database: Database | None = None,
) -> FastAPI:
    resolved_settings = settings or get_settings()
    configure_logging(resolved_settings.log_level)

    resolved_database = database or Database(resolved_settings.database_url)
    storage = MinioStorage(
        endpoint=resolved_settings.minio_endpoint,
        access_key=resolved_settings.minio_access_key.get_secret_value(),
        secret_key=resolved_settings.minio_secret_key.get_secret_value(),
        secure=resolved_settings.minio_secure,
        bucket=resolved_settings.minio_bucket,
    )
    resolved_readiness = readiness_checker or ReadinessService(
        resolved_database, storage
    )

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        yield
        await resolved_database.close()

    app = FastAPI(
        title=resolved_settings.app_name,
        version="0.1.0",
        lifespan=lifespan,
    )
    app.state.database = resolved_database
    app.state.object_storage = storage
    app.state.readiness_checker = resolved_readiness
    app.state.password_manager = PasswordManager()
    app.state.token_manager = TokenManager(resolved_settings)
    app.state.login_rate_limiter = LoginRateLimiter.from_settings(resolved_settings)
    app.add_middleware(RequestIdMiddleware)
    register_error_handlers(app)
    app.include_router(api_v1_router, prefix=resolved_settings.api_prefix)
    return app


app = create_app()
