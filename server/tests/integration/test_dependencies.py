import asyncio
import os
from uuid import uuid4

import pytest
from sqlalchemy import delete

from inknest_server.config import Settings
from inknest_server.db import Database
from inknest_server.models.auth import User
from inknest_server.repositories import (
    ContentRepository,
    ContentSaveResult,
    LibraryRepository,
    RevisionConflictError,
)
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

            first_notebook = await repository.create_notebook(
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
            content_repository = ContentRepository(session)
            first_revision = await content_repository.save_notebook_content(
                user_id=first_user.id,
                notebook_id=first_notebook.id,
                base_revision=0,
                content={"id": first_notebook.id, "pageIds": ["page-1"]},
            )
            second_revision = await content_repository.save_notebook_content(
                user_id=first_user.id,
                notebook_id=first_notebook.id,
                base_revision=1,
                content={"id": first_notebook.id, "pageIds": ["page-1", "page-2"]},
            )
            history = await content_repository.list_revisions(
                user_id=first_user.id,
                resource_type="notebook",
                resource_id=first_notebook.id,
            )

            assert first_revision.revision == 1
            assert second_revision.revision == 2
            assert [item.revision for item in history] == [2, 1]
            await transaction.rollback()
    finally:
        await database.close()


@pytest.mark.asyncio
async def test_postgres_serializes_concurrent_content_revisions() -> None:
    database = Database(Settings().database_url)
    suffix = uuid4().hex
    user_id = None

    try:
        async with database.session() as setup_session:
            user = User(
                email=f"phase3-revision-{suffix}@example.com",
                password_hash="integration-test-password-hash",
            )
            setup_session.add(user)
            await setup_session.flush()
            user_id = user.id
            notebook = await LibraryRepository(setup_session).create_notebook(
                user_id=user.id,
                notebook_id=f"concurrent-{suffix}",
                title="Concurrent revision test",
                layout_mode="paged",
            )
            notebook_id = notebook.id
            await setup_session.commit()

        async def save(content_label: str) -> ContentSaveResult:
            async with database.session() as session:
                async with session.begin():
                    return await ContentRepository(session).save_notebook_content(
                        user_id=user_id,
                        notebook_id=notebook_id,
                        base_revision=0,
                        content={"id": notebook_id, "label": content_label},
                    )

        results = await asyncio.gather(
            save("first"), save("second"), return_exceptions=True
        )
        successes = [
            result for result in results if isinstance(result, ContentSaveResult)
        ]
        conflicts = [
            result for result in results if isinstance(result, RevisionConflictError)
        ]

        assert len(successes) == 1
        assert successes[0].revision == 1
        assert len(conflicts) == 1
        assert conflicts[0].current_revision == 1
    finally:
        if user_id is not None:
            async with database.session() as cleanup_session:
                await cleanup_session.execute(delete(User).where(User.id == user_id))
                await cleanup_session.commit()
        await database.close()
