import os

import pytest

from inknest_server.config import Settings
from inknest_server.db import Database
from inknest_server.services.readiness import ReadinessService
from inknest_server.storage import MinioStorage

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(
        os.getenv("INKNEST_RUN_INTEGRATION") != "1",
        reason="set INKNEST_RUN_INTEGRATION=1 with PostgreSQL and MinIO running",
    ),
]


@pytest.mark.asyncio
async def test_postgres_and_minio_are_ready() -> None:
    settings = Settings()
    database = Database(settings.database_url)
    storage = MinioStorage(
        endpoint=settings.minio_endpoint,
        access_key=settings.minio_access_key.get_secret_value(),
        secret_key=settings.minio_secret_key.get_secret_value(),
        secure=settings.minio_secure,
        bucket=settings.minio_bucket,
    )
    readiness = ReadinessService(database, storage)

    try:
        checks = await readiness.check()
    finally:
        await database.close()

    assert checks == {
        "database": {"status": "ok"},
        "objectStorage": {"status": "ok"},
    }
