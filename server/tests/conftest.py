from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import SecretStr
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server import models  # noqa: F401
from inknest_server.config import Settings
from inknest_server.db import Database
from inknest_server.db.base import Base
from inknest_server.main import create_app
from inknest_server.services.readiness import ReadinessChecks


class HealthyReadinessChecker:
    async def check(self) -> ReadinessChecks:
        return {
            "database": {"status": "ok"},
            "objectStorage": {"status": "ok"},
        }


@pytest.fixture
def test_settings() -> Settings:
    return Settings(
        environment="test",
        database_url="sqlite+aiosqlite:///:memory:",
        jwt_secret=SecretStr("test-only-jwt-secret-that-is-at-least-32-characters"),
        login_rate_limit_account_attempts=2,
        login_rate_limit_ip_attempts=100,
        login_rate_limit_window_seconds=60,
    )


@pytest.fixture
async def database(test_settings: Settings) -> AsyncIterator[Database]:
    database = Database(test_settings.database_url)
    async with database.engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    yield database
    await database.close()


@pytest.fixture
async def db_session(database: Database) -> AsyncIterator[AsyncSession]:
    async with database.session() as session:
        yield session


@pytest.fixture
async def client(
    test_settings: Settings, database: Database
) -> AsyncIterator[AsyncClient]:
    app = create_app(
        settings=test_settings,
        readiness_checker=HealthyReadinessChecker(),
        database=database,
    )
    transport = ASGITransport(app=app)
    async with app.router.lifespan_context(app):
        async with AsyncClient(
            transport=transport,
            base_url="http://testserver",
        ) as test_client:
            yield test_client
