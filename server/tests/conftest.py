from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient

from inknest_server.config import Settings
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
    return Settings(environment="test")


@pytest.fixture
async def client(test_settings: Settings) -> AsyncIterator[AsyncClient]:
    app = create_app(
        settings=test_settings,
        readiness_checker=HealthyReadinessChecker(),
    )
    transport = ASGITransport(app=app)
    async with app.router.lifespan_context(app):
        async with AsyncClient(
            transport=transport,
            base_url="http://testserver",
        ) as test_client:
            yield test_client
