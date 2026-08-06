from datetime import UTC, datetime, timedelta
from uuid import uuid4

from conftest import FakeObjectStorage
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.assets import AssetUploadService
from inknest_server.assets.cleanup import AssetCleanupService
from inknest_server.config import Settings
from inknest_server.models import (
    Asset,
    AssetGarbageCollectionCandidate,
    AssetUpload,
    Notebook,
    User,
)


async def test_cleanup_is_dry_run_by_default_and_quarantines_orphans(
    db_session: AsyncSession,
    object_storage: FakeObjectStorage,
    test_settings: Settings,
) -> None:
    now = datetime(2026, 8, 6, 12, tzinfo=UTC)
    user = User(
        email="cleanup@example.com",
        password_hash="not-used-by-this-test",
    )
    db_session.add(user)
    await db_session.flush()
    notebook = Notebook(
        id="cleanup-notebook",
        user_id=user.id,
        title="Cleanup test",
        layout_mode="paged",
    )
    db_session.add(notebook)
    await db_session.flush()
    user_id = user.id
    notebook_id = notebook.id

    upload_id = uuid4()
    staging_key = f"users/{user.id}/uploads/{upload_id}/unfinished.png"
    upload = AssetUpload(
        id=upload_id,
        user_id=user_id,
        notebook_id=notebook_id,
        asset_id="unfinished-asset",
        kind="image",
        original_filename="unfinished.png",
        staging_object_key=staging_key,
        content_type="image/png",
        expected_byte_size=4,
        expected_sha256="a" * 64,
        status="pending",
        expires_at=now - timedelta(hours=25),
        upload_url_expires_at=now - timedelta(hours=25),
    )
    db_session.add(upload)

    referenced_key = (
        f"users/{user.id}/notebooks/{notebook.id}/images/ready-asset/ready.png"
    )
    db_session.add(
        Asset(
            id="ready-asset",
            user_id=user.id,
            notebook_id=notebook.id,
            kind="image",
            original_filename="ready.png",
            object_key=referenced_key,
            content_type="image/png",
            byte_size=4,
            sha256="b" * 64,
        )
    )
    await db_session.commit()

    orphan_key = (
        f"users/{user.id}/notebooks/{notebook.id}/images/orphan-asset/orphan.png"
    )
    object_storage.put_object(staging_key, b"test", content_type="image/png")
    object_storage.put_object(referenced_key, b"test", content_type="image/png")
    object_storage.put_object(orphan_key, b"test", content_type="image/png")

    service = AssetCleanupService(db_session, object_storage, test_settings)
    preview = await service.run(execute=False, now=now)

    assert preview.mode == "dry-run"
    assert preview.expired_sessions == 1
    assert preview.eligible_staging_objects == 1
    assert preview.discovered_orphan_objects == 1
    assert preview.deleted_staging_objects == 0
    assert staging_key in object_storage.objects
    assert await db_session.scalar(select(AssetGarbageCollectionCandidate)) is None

    executed = await service.run(execute=True, now=now)
    await db_session.refresh(upload)
    candidate = await db_session.scalar(select(AssetGarbageCollectionCandidate))

    assert executed.mode == "execute"
    assert executed.deleted_staging_objects == 1
    assert upload.status == "expired"
    assert upload.staging_deleted_at is not None
    assert upload.staging_deleted_at.replace(tzinfo=UTC) == now
    assert upload.cleanup_attempts == 1
    assert staging_key not in object_storage.objects
    assert candidate is not None
    assert candidate.object_key == orphan_key
    assert candidate.status == "pending"
    assert candidate.eligible_after.replace(tzinfo=UTC) == now + timedelta(days=7)
    assert referenced_key in object_storage.objects

    retried = await AssetUploadService(
        db_session,
        object_storage,
        test_settings,
    ).create_upload_session(
        user_id=user_id,
        device_id=uuid4(),
        notebook_id=notebook_id,
        asset_id=upload.asset_id,
        kind=upload.kind,
        filename=upload.original_filename,
        content_type=upload.content_type,
        byte_size=upload.expected_byte_size,
        sha256=upload.expected_sha256,
    )
    assert retried.upload.status == "pending"
    assert retried.upload.staging_deleted_at is None

    after_quarantine = await service.run(
        execute=True,
        now=now + timedelta(days=8),
    )
    await db_session.refresh(candidate)

    assert after_quarantine.deleted_orphan_objects == 1
    assert candidate.status == "deleted"
    assert candidate.delete_attempts == 1
    assert orphan_key not in object_storage.objects
    assert referenced_key in object_storage.objects


async def test_cleanup_rechecks_reference_before_deleting_quarantined_object(
    db_session: AsyncSession,
    object_storage: FakeObjectStorage,
    test_settings: Settings,
) -> None:
    now = datetime(2026, 8, 6, 12, tzinfo=UTC)
    user = User(
        email="cleanup-protection@example.com",
        password_hash="not-used-by-this-test",
    )
    db_session.add(user)
    await db_session.flush()
    notebook = Notebook(
        id="protected-notebook",
        user_id=user.id,
        title="Protected cleanup test",
        layout_mode="paged",
    )
    db_session.add(notebook)
    await db_session.commit()

    object_key = f"users/{user.id}/notebooks/{notebook.id}/images/late-asset/late.png"
    object_storage.put_object(object_key, b"late", content_type="image/png")
    service = AssetCleanupService(db_session, object_storage, test_settings)
    await service.run(execute=True, now=now)

    db_session.add(
        Asset(
            id="late-asset",
            user_id=user.id,
            notebook_id=notebook.id,
            kind="image",
            original_filename="late.png",
            object_key=object_key,
            content_type="image/png",
            byte_size=4,
            sha256="c" * 64,
        )
    )
    await db_session.commit()

    result = await service.run(execute=True, now=now + timedelta(days=8))
    candidate = await db_session.scalar(select(AssetGarbageCollectionCandidate))

    assert result.protected_objects == 1
    assert result.deleted_orphan_objects == 0
    assert candidate is not None
    assert candidate.status == "protected"
    assert object_key in object_storage.objects
