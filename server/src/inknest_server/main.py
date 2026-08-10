from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from inknest_server.api.v1.router import router as api_v1_router
from inknest_server.auth import LoginRateLimiter, PasswordManager, TokenManager
from inknest_server.config import Settings, get_settings
from inknest_server.db import (
    AlembicSchemaVersionChecker,
    Database,
    SchemaVersionChecker,
)
from inknest_server.errors import register_error_handlers
from inknest_server.logging_config import configure_logging
from inknest_server.middleware.request_id import RequestIdMiddleware
from inknest_server.services.readiness import ReadinessChecker, ReadinessService
from inknest_server.storage import MinioStorage, ObjectStorage


def create_app(
    *,
    settings: Settings | None = None,
    readiness_checker: ReadinessChecker | None = None,
    database: Database | None = None,
    object_storage: ObjectStorage | None = None,
    schema_version_checker: SchemaVersionChecker | None = None,
) -> FastAPI:
    resolved_settings = settings or get_settings()
    configure_logging(resolved_settings.log_level)

    resolved_database = database or Database(resolved_settings.database_url)
    storage = object_storage or MinioStorage(
        endpoint=resolved_settings.minio_endpoint,
        public_endpoint=resolved_settings.minio_public_endpoint,
        access_key=resolved_settings.minio_access_key.get_secret_value(),
        secret_key=resolved_settings.minio_secret_key.get_secret_value(),
        secure=resolved_settings.minio_secure,
        public_secure=resolved_settings.minio_public_secure,
        region=resolved_settings.minio_region,
        bucket=resolved_settings.minio_bucket,
    )
    resolved_readiness = readiness_checker or ReadinessService(
        resolved_database, storage
    )
    resolved_schema_version_checker = schema_version_checker
    if (
        resolved_schema_version_checker is None
        and resolved_settings.environment != "test"
    ):
        resolved_schema_version_checker = AlembicSchemaVersionChecker(resolved_database)

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        try:
            if resolved_schema_version_checker is not None:
                await resolved_schema_version_checker.check()
            yield
        finally:
            await resolved_database.close()

    app = FastAPI(
        title=resolved_settings.app_name,
        version="0.1.0",
        lifespan=lifespan,
    )
    app.state.database = resolved_database
    app.state.settings = resolved_settings
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
