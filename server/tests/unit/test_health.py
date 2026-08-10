from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient

from inknest_server.config import Settings
from inknest_server.db import SchemaVersionMismatchError
from inknest_server.errors import DependenciesUnavailableError
from inknest_server.main import create_app
from inknest_server.services.readiness import ReadinessChecks


class UnhealthyReadinessChecker:
    async def check(self) -> ReadinessChecks:
        raise DependenciesUnavailableError(
            {
                "database": {"status": "ok"},
                "objectStorage": {
                    "status": "error",
                    "reason": "ConnectionError",
                },
            }
        )


class RecordingSchemaVersionChecker:
    def __init__(self) -> None:
        self.call_count = 0

    async def check(self) -> None:
        self.call_count += 1


class FailingSchemaVersionChecker:
    async def check(self) -> None:
        raise SchemaVersionMismatchError(
            current_heads=("old-revision",),
            expected_head="current-revision",
        )


async def test_liveness_is_independent_from_external_services(
    client: AsyncClient,
) -> None:
    response = await client.get("/api/v1/health/live")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "inknest-server"}
    assert response.headers["x-request-id"]


async def test_readiness_reports_all_required_dependencies(client: AsyncClient) -> None:
    response = await client.get("/api/v1/health/ready")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ready",
        "checks": {
            "database": {"status": "ok"},
            "objectStorage": {"status": "ok"},
        },
    }


async def test_readiness_uses_structured_error_response() -> None:
    app = create_app(
        settings=Settings(environment="test"),
        readiness_checker=UnhealthyReadinessChecker(),
    )
    transport = ASGITransport(app=app)

    async with app.router.lifespan_context(app):
        async with AsyncClient(
            transport=transport,
            base_url="http://testserver",
        ) as client:
            response = await client.get(
                "/api/v1/health/ready",
                headers={"x-request-id": "readiness-test"},
            )

    body: dict[str, Any] = response.json()
    assert response.status_code == 503
    assert response.headers["x-request-id"] == "readiness-test"
    assert body["error"]["code"] == "dependencies_unavailable"
    assert body["error"]["requestId"] == "readiness-test"
    assert body["error"]["details"]["checks"]["objectStorage"] == {
        "status": "error",
        "reason": "ConnectionError",
    }


async def test_lifespan_checks_schema_version_before_serving_requests() -> None:
    checker = RecordingSchemaVersionChecker()
    app = create_app(
        settings=Settings(environment="test"),
        readiness_checker=UnhealthyReadinessChecker(),
        schema_version_checker=checker,
    )

    async with app.router.lifespan_context(app):
        assert checker.call_count == 1


async def test_lifespan_refuses_to_start_with_a_schema_mismatch() -> None:
    app = create_app(
        settings=Settings(environment="test"),
        schema_version_checker=FailingSchemaVersionChecker(),
    )

    with pytest.raises(SchemaVersionMismatchError, match="old-revision"):
        async with app.router.lifespan_context(app):
            pytest.fail("a mismatched database must not serve requests")


async def test_http_errors_use_structured_error_response(
    client: AsyncClient,
) -> None:
    response = await client.get(
        "/api/v1/missing",
        headers={"x-request-id": "missing-test"},
    )

    assert response.status_code == 404
    assert response.json() == {
        "error": {
            "code": "not_found",
            "message": "Not Found",
            "requestId": "missing-test",
        }
    }
