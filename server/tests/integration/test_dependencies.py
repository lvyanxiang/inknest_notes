import asyncio
import hashlib
import os
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import delete, func, select

from inknest_server.assets import AssetUploadService
from inknest_server.assets.cleanup import AssetCleanupService
from inknest_server.config import Settings
from inknest_server.db import Database
from inknest_server.models import (
    Asset,
    AssetGarbageCollectionCandidate,
    AssetUpload,
    Conflict,
    Device,
    Notebook,
    SyncChange,
    SyncCommit,
    Tombstone,
    User,
)
from inknest_server.repositories import (
    ContentRepository,
    ContentSaveResult,
    LibraryRepository,
    RevisionConflictError,
    SyncChangeRepository,
)
from inknest_server.services.readiness import ReadinessService
from inknest_server.storage import MinioStorage
from inknest_server.sync import SyncCommitRequest, SyncCursorCodec
from inknest_server.sync.service import SyncService

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
        public_endpoint=settings.minio_public_endpoint,
        access_key=settings.minio_access_key.get_secret_value(),
        secret_key=settings.minio_secret_key.get_secret_value(),
        secure=settings.minio_secure,
        public_secure=settings.minio_public_secure,
        region=settings.minio_region,
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
@pytest.mark.parametrize(
    ("kind", "filename", "content_type", "content"),
    [
        ("pdf", "integration.pdf", "application/pdf", b"%PDF-1.7\ninknest\n"),
        ("image", "integration.png", "image/png", b"\x89PNG\r\ninknest"),
        ("audio", "integration.m4a", "audio/mp4", b"inknest-m4a-audio"),
    ],
    ids=["pdf", "image", "audio"],
)
async def test_presigned_asset_round_trip(
    kind: str,
    filename: str,
    content_type: str,
    content: bytes,
) -> None:
    settings = Settings()
    database = Database(settings.database_url)
    storage = MinioStorage(
        endpoint=settings.minio_endpoint,
        public_endpoint=settings.minio_public_endpoint,
        access_key=settings.minio_access_key.get_secret_value(),
        secret_key=settings.minio_secret_key.get_secret_value(),
        secure=settings.minio_secure,
        public_secure=settings.minio_public_secure,
        region=settings.minio_region,
        bucket=settings.minio_bucket,
    )
    suffix = uuid4().hex
    user_id = None
    object_keys: set[str] = set()
    try:
        async with database.session() as session:
            user = User(
                email=f"phase3-upload-{suffix}@example.com",
                password_hash="integration-test-password-hash",
            )
            session.add(user)
            await session.flush()
            user_id = user.id
            device = Device(user_id=user.id, name="Integration iPad", platform="ios")
            session.add(device)
            await session.flush()
            notebook = await LibraryRepository(session).create_notebook(
                user_id=user.id,
                notebook_id=f"upload-{suffix}",
                title="Presigned upload test",
                layout_mode="paged",
            )
            await session.commit()

            service = AssetUploadService(session, storage, settings)
            result = await service.create_upload_session(
                user_id=user.id,
                device_id=device.id,
                notebook_id=notebook.id,
                asset_id=f"asset-{kind}-{suffix}",
                kind=kind,
                filename=filename,
                content_type=content_type,
                byte_size=len(content),
                sha256=hashlib.sha256(content).hexdigest(),
            )
            object_keys.add(result.upload.staging_object_key)

            async with AsyncClient() as http_client:
                upload_response = await http_client.put(
                    result.upload_url,
                    content=content,
                    headers={"Content-Type": content_type},
                )

            await session.refresh(result.upload)
            asset = await session.get(Asset, (f"asset-{kind}-{suffix}", user.id))
            persisted_upload = await session.get(AssetUpload, result.upload.id)

            assert upload_response.status_code == 200
            assert persisted_upload is not None
            assert persisted_upload.status == "pending"
            assert asset is None
            completed = await service.complete_upload_session(
                user_id=user.id,
                upload_id=result.upload.id,
            )
            retry = await service.complete_upload_session(
                user_id=user.id,
                upload_id=result.upload.id,
            )
            object_keys.add(completed.object_key)
            download = await service.create_download_url(
                user_id=user.id,
                asset_id=completed.id,
            )
            async with AsyncClient() as http_client:
                download_response = await http_client.get(download.download_url)

            await session.refresh(result.upload)
            assert completed.id == retry.id
            assert completed.byte_size == len(content)
            assert completed.sha256 == hashlib.sha256(content).hexdigest()
            assert result.upload.status == "completed"
            assert result.upload.completed_at is not None
            assert (
                await storage.stat_object(completed.object_key)
            ).content_type == content_type
            assert download.asset.id == completed.id
            assert download_response.status_code == 200
            assert download_response.content == content
            assert download_response.headers["content-type"] == content_type
    finally:
        for object_key in object_keys:
            await storage.delete_object(object_key)
        if user_id is not None:
            async with database.session() as cleanup_session:
                await cleanup_session.execute(delete(User).where(User.id == user_id))
                await cleanup_session.commit()
        await database.close()


@pytest.mark.asyncio
async def test_asset_cleanup_tracks_and_deletes_real_minio_objects() -> None:
    settings = Settings()
    database = Database(settings.database_url)
    storage = MinioStorage(
        endpoint=settings.minio_endpoint,
        public_endpoint=settings.minio_public_endpoint,
        access_key=settings.minio_access_key.get_secret_value(),
        secret_key=settings.minio_secret_key.get_secret_value(),
        secure=settings.minio_secure,
        public_secure=settings.minio_public_secure,
        region=settings.minio_region,
        bucket=settings.minio_bucket,
    )
    suffix = uuid4().hex
    now = datetime.now(UTC)
    user_id = None
    candidate_id = None
    staging_key = ""
    orphan_key = ""
    try:
        async with database.session() as session:
            user = User(
                email=f"phase3-cleanup-{suffix}@example.com",
                password_hash="integration-test-password-hash",
            )
            session.add(user)
            await session.flush()
            user_id = user.id
            notebook = Notebook(
                id=f"cleanup-{suffix}",
                user_id=user.id,
                title="Cleanup integration test",
                layout_mode="paged",
            )
            session.add(notebook)
            await session.flush()

            upload_id = uuid4()
            staging_key = f"users/{user.id}/uploads/{upload_id}/unfinished.png"
            orphan_key = (
                f"users/{user.id}/notebooks/{notebook.id}/images/"
                f"orphan-{suffix}/orphan.png"
            )
            session.add(
                AssetUpload(
                    id=upload_id,
                    user_id=user.id,
                    notebook_id=notebook.id,
                    asset_id=f"unfinished-{suffix}",
                    kind="image",
                    original_filename="unfinished.png",
                    staging_object_key=staging_key,
                    content_type="image/png",
                    expected_byte_size=4,
                    expected_sha256=hashlib.sha256(b"test").hexdigest(),
                    status="pending",
                    expires_at=now - timedelta(hours=25),
                    upload_url_expires_at=now - timedelta(hours=25),
                )
            )
            await session.commit()

            async with AsyncClient() as http_client:
                for object_key in (staging_key, orphan_key):
                    upload_url = await storage.create_upload_url(
                        object_key,
                        expires=timedelta(minutes=5),
                    )
                    response = await http_client.put(
                        upload_url,
                        content=b"test",
                        headers={"Content-Type": "image/png"},
                    )
                    assert response.status_code == 200

            service = AssetCleanupService(session, storage, settings)
            prefix = f"users/{user.id}/"
            preview = await service.run(
                execute=False,
                now=now,
                object_prefix=prefix,
            )
            assert preview.eligible_staging_objects == 1
            assert preview.discovered_orphan_objects == 1
            await storage.stat_object(staging_key)

            first_run = await service.run(
                execute=True,
                now=now,
                object_prefix=prefix,
            )
            candidate = await session.scalar(
                select(AssetGarbageCollectionCandidate).where(
                    AssetGarbageCollectionCandidate.object_key == orphan_key
                )
            )
            assert first_run.deleted_staging_objects == 1
            assert candidate is not None
            candidate_id = candidate.id
            assert candidate.status == "pending"

            second_run = await service.run(
                execute=True,
                now=now + timedelta(days=8),
                object_prefix=prefix,
            )
            assert second_run.deleted_orphan_objects == 1
            await session.refresh(candidate)
            assert candidate.status == "deleted"
    finally:
        for object_key in (staging_key, orphan_key):
            if object_key:
                await storage.delete_object(object_key)
        async with database.session() as cleanup_session:
            if candidate_id is not None:
                await cleanup_session.execute(
                    delete(AssetGarbageCollectionCandidate).where(
                        AssetGarbageCollectionCandidate.id == candidate_id
                    )
                )
            if user_id is not None:
                await cleanup_session.execute(delete(User).where(User.id == user_id))
            await cleanup_session.commit()
        await database.close()


@pytest.mark.asyncio
async def test_sync_change_sequence_is_persisted_and_user_scoped() -> None:
    database = Database(Settings().database_url)
    suffix = uuid4().hex
    first_user_id = None
    second_user_id = None
    try:
        async with database.session() as session:
            first_user = User(
                email=f"sync-first-{suffix}@example.com",
                password_hash="integration-test-password-hash",
            )
            second_user = User(
                email=f"sync-second-{suffix}@example.com",
                password_hash="integration-test-password-hash",
            )
            session.add_all([first_user, second_user])
            await session.flush()
            first_user_id = first_user.id
            second_user_id = second_user.id
            repository = SyncChangeRepository(session)
            first = await repository.append_upsert(
                user_id=first_user.id,
                resource_type="folder",
                resource_id="folder-1",
                payload={"id": "folder-1", "name": "First"},
            )
            second = await repository.append_upsert(
                user_id=first_user.id,
                resource_type="folder",
                resource_id="folder-2",
                payload={"id": "folder-2", "name": "Second"},
            )
            await repository.append_upsert(
                user_id=second_user.id,
                resource_type="folder",
                resource_id="private-folder",
                payload={"id": "private-folder", "name": "Private"},
            )
            await session.commit()

            first_user_changes = await repository.list_after(
                user_id=first_user.id,
                after_sequence=first.sequence,
                limit=10,
            )
            second_user_changes = await repository.list_after(
                user_id=second_user.id,
                after_sequence=0,
                limit=10,
            )

            assert second.sequence > first.sequence
            assert [item.change_id for item in first_user_changes] == [second.change_id]
            assert [item.resource_id for item in second_user_changes] == [
                "private-folder"
            ]
    finally:
        async with database.session() as cleanup_session:
            if first_user_id is not None:
                await cleanup_session.execute(
                    delete(User).where(User.id == first_user_id)
                )
            if second_user_id is not None:
                await cleanup_session.execute(
                    delete(User).where(User.id == second_user_id)
                )
            await cleanup_session.commit()
        await database.close()


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


@pytest.mark.asyncio
async def test_postgres_replays_concurrent_sync_commits_once() -> None:
    settings = Settings()
    database = Database(settings.database_url)
    suffix = uuid4().hex
    user_id = None

    try:
        async with database.session() as setup_session:
            user = User(
                email=f"phase4-sync-commit-{suffix}@example.com",
                password_hash="integration-test-password-hash",
            )
            setup_session.add(user)
            await setup_session.flush()
            user_id = user.id
            device = Device(user_id=user.id, name="Integration iPad", platform="ios")
            setup_session.add(device)
            await setup_session.flush()
            notebook = await LibraryRepository(setup_session).create_notebook(
                user_id=user.id,
                notebook_id=f"sync-commit-{suffix}",
                title="Concurrent sync commit",
                layout_mode="paged",
            )
            latest_sequence = await SyncChangeRepository(setup_session).latest_sequence(
                user_id=user.id
            )
            await setup_session.commit()
            device_id = device.id
            notebook_id = notebook.id

        codec = SyncCursorCodec(settings)
        request = SyncCommitRequest.model_validate(
            {
                "deviceId": str(device_id),
                "idempotencyKey": f"concurrent-{suffix}",
                "baseCursor": codec.encode(
                    user_id=user_id,
                    sequence=latest_sequence,
                ),
                "operations": [
                    {
                        "operationId": "notebook-content",
                        "operation": "upsert",
                        "resourceType": "notebook",
                        "resourceId": notebook_id,
                        "baseRevision": 0,
                        "content": {"label": "written-once"},
                    }
                ],
            }
        )

        async def commit() -> bool:
            async with database.session() as session:
                result = await SyncService(
                    session,
                    SyncChangeRepository(session),
                    codec,
                ).commit(
                    user_id=user_id,
                    authenticated_device_id=device_id,
                    request=request,
                )
                return result.replayed

        replayed_flags = await asyncio.gather(commit(), commit())

        async with database.session() as verify_session:
            revision = await verify_session.scalar(
                select(Notebook.revision).where(
                    Notebook.id == notebook_id,
                    Notebook.user_id == user_id,
                )
            )
            commit_count = await verify_session.scalar(
                select(func.count())
                .select_from(SyncCommit)
                .where(SyncCommit.user_id == user_id)
            )
            content_change_count = await verify_session.scalar(
                select(func.count())
                .select_from(SyncChange)
                .where(
                    SyncChange.user_id == user_id,
                    SyncChange.resource_id == notebook_id,
                    SyncChange.revision == 1,
                )
            )

        assert sorted(replayed_flags) == [False, True]
        assert revision == 1
        assert commit_count == 1
        assert content_change_count == 1
    finally:
        if user_id is not None:
            async with database.session() as cleanup_session:
                await cleanup_session.execute(delete(User).where(User.id == user_id))
                await cleanup_session.commit()
        await database.close()


@pytest.mark.asyncio
async def test_postgres_replays_one_conflict_copy_for_concurrent_retries() -> None:
    settings = Settings()
    database = Database(settings.database_url)
    suffix = uuid4().hex
    user_id = None

    try:
        async with database.session() as setup_session:
            user = User(
                email=f"phase4-sync-conflict-{suffix}@example.com",
                password_hash="integration-test-password-hash",
            )
            setup_session.add(user)
            await setup_session.flush()
            user_id = user.id
            device = Device(user_id=user.id, name="Integration iPad", platform="ios")
            setup_session.add(device)
            await setup_session.flush()
            notebook = await LibraryRepository(setup_session).create_notebook(
                user_id=user.id,
                notebook_id=f"sync-conflict-{suffix}",
                title="Concurrent conflict retry",
                layout_mode="paged",
            )
            await ContentRepository(setup_session).save_notebook_content(
                user_id=user.id,
                notebook_id=notebook.id,
                base_revision=0,
                content={"label": "server-version"},
            )
            latest_sequence = await SyncChangeRepository(setup_session).latest_sequence(
                user_id=user.id
            )
            await setup_session.commit()
            device_id = device.id
            notebook_id = notebook.id

        codec = SyncCursorCodec(settings)
        request = SyncCommitRequest.model_validate(
            {
                "deviceId": str(device_id),
                "idempotencyKey": f"conflict-retry-{suffix}",
                "baseCursor": codec.encode(
                    user_id=user_id,
                    sequence=latest_sequence,
                ),
                "operations": [
                    {
                        "operationId": "offline-notebook-content",
                        "operation": "upsert",
                        "resourceType": "notebook",
                        "resourceId": notebook_id,
                        "baseRevision": 0,
                        "content": {"label": "offline-version"},
                    }
                ],
            }
        )

        async def commit() -> tuple[bool, str, str]:
            async with database.session() as session:
                result = await SyncService(
                    session,
                    SyncChangeRepository(session),
                    codec,
                ).commit(
                    user_id=user_id,
                    authenticated_device_id=device_id,
                    request=request,
                )
                operation = result.results[0]
                assert operation.conflict is not None
                return (
                    result.replayed,
                    operation.outcome,
                    str(operation.conflict.id),
                )

        results = await asyncio.gather(commit(), commit())

        async with database.session() as verify_session:
            conflict_count = await verify_session.scalar(
                select(func.count())
                .select_from(Conflict)
                .where(Conflict.user_id == user_id)
            )
            conflict_change_count = await verify_session.scalar(
                select(func.count())
                .select_from(SyncChange)
                .where(
                    SyncChange.user_id == user_id,
                    SyncChange.resource_type == "conflict",
                )
            )
            original = await verify_session.scalar(
                select(Notebook).where(
                    Notebook.id == notebook_id,
                    Notebook.user_id == user_id,
                )
            )

        assert sorted(result[0] for result in results) == [False, True]
        assert {result[1] for result in results} == {"conflict"}
        assert len({result[2] for result in results}) == 1
        assert conflict_count == 1
        assert conflict_change_count == 1
        assert original is not None
        assert original.revision == 1
        assert original.content == {"label": "server-version"}
    finally:
        if user_id is not None:
            async with database.session() as cleanup_session:
                await cleanup_session.execute(delete(User).where(User.id == user_id))
                await cleanup_session.commit()
        await database.close()


@pytest.mark.asyncio
async def test_postgres_delete_edit_race_preserves_the_edit() -> None:
    settings = Settings()
    database = Database(settings.database_url)
    suffix = uuid4().hex
    user_id = None

    try:
        async with database.session() as setup_session:
            user = User(
                email=f"phase4-delete-edit-{suffix}@example.com",
                password_hash="integration-test-password-hash",
            )
            setup_session.add(user)
            await setup_session.flush()
            deleting_device = Device(
                user_id=user.id, name="Deleting iPad", platform="ios"
            )
            editing_device = Device(
                user_id=user.id, name="Editing iPad", platform="ios"
            )
            setup_session.add_all([deleting_device, editing_device])
            await setup_session.flush()
            notebook = await LibraryRepository(setup_session).create_notebook(
                user_id=user.id,
                notebook_id=f"delete-edit-{suffix}",
                title="Delete/edit race",
                layout_mode="paged",
            )
            await ContentRepository(setup_session).save_notebook_content(
                user_id=user.id,
                notebook_id=notebook.id,
                base_revision=0,
                content={"label": "base"},
                device_id=editing_device.id,
            )
            latest_sequence = await SyncChangeRepository(setup_session).latest_sequence(
                user_id=user.id
            )
            await setup_session.commit()
            user_id = user.id
            notebook_id = notebook.id
            deleting_device_id = deleting_device.id
            editing_device_id = editing_device.id

        codec = SyncCursorCodec(settings)
        base_cursor = codec.encode(user_id=user_id, sequence=latest_sequence)
        delete_request = SyncCommitRequest.model_validate(
            {
                "deviceId": str(deleting_device_id),
                "idempotencyKey": f"delete-{suffix}",
                "baseCursor": base_cursor,
                "operations": [
                    {
                        "operationId": "delete-notebook",
                        "operation": "delete",
                        "resourceType": "notebook",
                        "resourceId": notebook_id,
                        "baseRevision": 1,
                    }
                ],
            }
        )
        edit_request = SyncCommitRequest.model_validate(
            {
                "deviceId": str(editing_device_id),
                "idempotencyKey": f"edit-{suffix}",
                "baseCursor": base_cursor,
                "operations": [
                    {
                        "operationId": "edit-notebook",
                        "operation": "upsert",
                        "resourceType": "notebook",
                        "resourceId": notebook_id,
                        "baseRevision": 1,
                        "content": {"label": "offline edit survives"},
                    }
                ],
            }
        )

        async def commit(
            request: SyncCommitRequest, device_id: UUID
        ) -> tuple[str, int]:
            async with database.session() as session:
                result = await SyncService(
                    session,
                    SyncChangeRepository(session),
                    codec,
                ).commit(
                    user_id=user_id,
                    authenticated_device_id=device_id,
                    request=request,
                )
                operation = result.results[0]
                return operation.outcome, operation.revision

        outcomes = await asyncio.gather(
            commit(delete_request, deleting_device_id),
            commit(edit_request, editing_device_id),
        )

        async with database.session() as verify_session:
            stored = await verify_session.scalar(
                select(Notebook).where(
                    Notebook.id == notebook_id,
                    Notebook.user_id == user_id,
                )
            )
            tombstones = list(
                await verify_session.scalars(
                    select(Tombstone).where(Tombstone.user_id == user_id)
                )
            )

        assert "delete_conflict" in {outcome for outcome, _ in outcomes}
        assert stored is not None
        assert stored.deleted_at is None
        assert stored.content == {"label": "offline edit survives"}
        assert len(tombstones) == 1
        assert tombstones[0].state == "restored"
        assert tombstones[0].resolution == "preserved_edit"
        assert tombstones[0].conflict_kind in {
            "delete_after_edit",
            "edit_after_delete",
        }
    finally:
        if user_id is not None:
            async with database.session() as cleanup_session:
                await cleanup_session.execute(delete(User).where(User.id == user_id))
                await cleanup_session.commit()
        await database.close()
