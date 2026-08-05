import os
from uuid import uuid4

import pytest

from inknest_server.config import Settings
from inknest_server.db import Database
from inknest_server.models.auth import User
from inknest_server.repositories import LibraryRepository
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


@pytest.mark.asyncio
async def test_library_repository_persists_owned_metadata_in_postgres() -> None:
    database = Database(Settings().database_url)
    suffix = uuid4().hex

    try:
        async with database.session() as session:
            transaction = await session.begin()
            first_user = User(
                email=f"phase3-first-{suffix}@example.com",
                password_hash="integration-test-password-hash",
            )
            second_user = User(
                email=f"phase3-second-{suffix}@example.com",
                password_hash="integration-test-password-hash",
            )
            session.add_all([first_user, second_user])
            await session.flush()
            repository = LibraryRepository(session)

            await repository.create_notebook(
                user_id=first_user.id,
                notebook_id="shared-local-id",
                title="First user's notebook",
                layout_mode="paged",
            )
            await repository.create_notebook(
                user_id=second_user.id,
                notebook_id="shared-local-id",
                title="Second user's notebook",
                layout_mode="paged",
            )

            assert (
                await repository.get_notebook(
                    user_id=first_user.id, notebook_id="shared-local-id"
                )
            ).title == "First user's notebook"
            assert (
                await repository.get_notebook(
                    user_id=second_user.id, notebook_id="shared-local-id"
                )
            ).title == "Second user's notebook"
            await transaction.rollback()
    finally:
        await database.close()
