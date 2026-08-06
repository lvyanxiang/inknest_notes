from typing import Any, cast
from uuid import UUID

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.config import Settings
from inknest_server.models import Notebook, Page, SyncChange, SyncCommit, User
from inknest_server.repositories import (
    ContentRepository,
    LibraryRepository,
    SyncChangeRepository,
)
from inknest_server.sync import InvalidSyncCursorError, SyncCursorCodec


async def register(client: AsyncClient, email: str) -> dict[str, Any]:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "correct-horse-battery-staple",
            "deviceName": "Test iPad",
            "platform": "ios",
        },
    )
    assert response.status_code == 201
    return cast(dict[str, Any], response.json())


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_sync_cursor_is_account_bound_and_tamper_evident(
    test_settings: Settings,
) -> None:
    codec = SyncCursorCodec(test_settings)
    first_user = UUID("11111111-1111-1111-1111-111111111111")
    second_user = UUID("22222222-2222-2222-2222-222222222222")
    cursor = codec.encode(user_id=first_user, sequence=42)

    assert codec.decode(cursor, user_id=first_user) == 42
    with pytest.raises(InvalidSyncCursorError):
        codec.decode(cursor, user_id=second_user)
    with pytest.raises(InvalidSyncCursorError):
        codec.decode(f"{cursor[:-1]}x", user_id=first_user)
    with pytest.raises(InvalidSyncCursorError):
        codec.decode("not-a-cursor", user_id=first_user)


async def test_library_and_revision_writes_append_transactional_changes(
    db_session: AsyncSession,
) -> None:
    user = User(email="sync-writes@example.com", password_hash="test-password-hash")
    db_session.add(user)
    await db_session.flush()
    library = LibraryRepository(db_session)
    notebook = await library.create_notebook(
        user_id=user.id,
        notebook_id="sync-notebook",
        title="Sync",
        layout_mode="paged",
    )
    page = await library.create_page(
        user_id=user.id,
        notebook_id=notebook.id,
        page_id="sync-page",
        position=0,
        width=768,
        height=1024,
        coordinate_space_version=1,
    )
    content: dict[str, object] = {"id": page.id, "strokes": []}
    repository = ContentRepository(db_session)
    first = await repository.save_page_content(
        user_id=user.id,
        page_id=page.id,
        base_revision=0,
        content=content,
    )
    retry = await repository.save_page_content(
        user_id=user.id,
        page_id=page.id,
        base_revision=0,
        content=content,
    )
    changes = await SyncChangeRepository(db_session).list_after(
        user_id=user.id,
        after_sequence=0,
        limit=10,
    )

    assert first.created_revision is True
    assert retry.created_revision is False
    assert [(item.resource_type, item.resource_id) for item in changes] == [
        ("notebook", notebook.id),
        ("page", page.id),
        ("page", page.id),
    ]
    assert changes[-1].revision == 1
    assert changes[-1].content_hash == first.content_hash
    assert changes[-1].payload is not None
    assert changes[-1].payload["content"] == content


async def test_sync_changes_endpoint_pages_and_isolates_accounts(
    client: AsyncClient,
    db_session: AsyncSession,
) -> None:
    first = await register(client, "sync-first@example.com")
    second = await register(client, "sync-second@example.com")
    first_user_id = UUID(first["user"]["id"])
    second_user_id = UUID(second["user"]["id"])
    repository = SyncChangeRepository(db_session)
    for index in range(3):
        await repository.append_upsert(
            user_id=first_user_id,
            resource_type="folder",
            resource_id=f"first-{index}",
            payload={"id": f"first-{index}", "name": f"Folder {index}"},
        )
    await repository.append_upsert(
        user_id=second_user_id,
        resource_type="folder",
        resource_id="second-only",
        payload={"id": "second-only", "name": "Private"},
    )
    await db_session.commit()

    unauthorized = await client.get("/api/v1/sync/changes")
    first_page = await client.get(
        "/api/v1/sync/changes?limit=2",
        headers=bearer(first["accessToken"]),
    )
    first_body = first_page.json()
    second_page = await client.get(
        "/api/v1/sync/changes",
        params={"cursor": first_body["nextCursor"], "limit": 2},
        headers=bearer(first["accessToken"]),
    )
    other_account = await client.get(
        "/api/v1/sync/changes",
        headers=bearer(second["accessToken"]),
    )
    cross_account_cursor = await client.get(
        "/api/v1/sync/changes",
        params={"cursor": first_body["nextCursor"]},
        headers=bearer(second["accessToken"]),
    )
    tampered_cursor = await client.get(
        "/api/v1/sync/changes",
        params={"cursor": f"{first_body['nextCursor'][:-1]}x"},
        headers=bearer(first["accessToken"]),
    )

    assert unauthorized.status_code == 401
    assert first_page.status_code == 200
    assert [item["resourceId"] for item in first_body["changes"]] == [
        "first-0",
        "first-1",
    ]
    assert first_body["hasMore"] is True
    assert [item["resourceId"] for item in second_page.json()["changes"]] == ["first-2"]
    assert second_page.json()["hasMore"] is False
    assert [item["resourceId"] for item in other_account.json()["changes"]] == [
        "second-only"
    ]
    assert cross_account_cursor.status_code == 400
    assert cross_account_cursor.json()["error"]["code"] == "sync_cursor_invalid"
    assert tampered_cursor.status_code == 400
    assert tampered_cursor.json()["error"]["code"] == "sync_cursor_invalid"


async def test_sync_commit_is_atomic_and_idempotent(
    client: AsyncClient,
    db_session: AsyncSession,
) -> None:
    registered = await register(client, "sync-commit@example.com")
    user_id = UUID(registered["user"]["id"])
    device_id = registered["device"]["id"]
    library = LibraryRepository(db_session)
    notebook = await library.create_notebook(
        user_id=user_id,
        notebook_id="commit-notebook",
        title="Commit",
        layout_mode="paged",
    )
    page = await library.create_page(
        user_id=user_id,
        notebook_id=notebook.id,
        page_id="commit-page",
        position=0,
        width=768,
        height=1024,
        coordinate_space_version=1,
    )
    await db_session.commit()
    initial_changes = await client.get(
        "/api/v1/sync/changes",
        headers=bearer(registered["accessToken"]),
    )
    base_cursor = initial_changes.json()["nextCursor"]
    payload = {
        "deviceId": device_id,
        "idempotencyKey": "commit-batch-1",
        "baseCursor": base_cursor,
        "operations": [
            {
                "operationId": "notebook-content-1",
                "operation": "upsert",
                "resourceType": "notebook",
                "resourceId": notebook.id,
                "baseRevision": 0,
                "content": {"schemaVersion": 1, "cover": "grid"},
            },
            {
                "operationId": "page-content-1",
                "operation": "upsert",
                "resourceType": "page",
                "resourceId": page.id,
                "baseRevision": 0,
                "content": {"schemaVersion": 1, "strokes": [{"id": "stroke-1"}]},
            },
        ],
    }

    committed = await client.post(
        "/api/v1/sync/commit",
        json=payload,
        headers=bearer(registered["accessToken"]),
    )
    first_body = committed.json()
    changes_after_first = await db_session.scalar(
        select(func.count())
        .select_from(SyncChange)
        .where(SyncChange.user_id == user_id)
    )
    replayed = await client.post(
        "/api/v1/sync/commit",
        json=payload,
        headers=bearer(registered["accessToken"]),
    )
    changes_after_replay = await db_session.scalar(
        select(func.count())
        .select_from(SyncChange)
        .where(SyncChange.user_id == user_id)
    )
    commit_rows = await db_session.scalar(
        select(func.count())
        .select_from(SyncCommit)
        .where(SyncCommit.user_id == user_id)
    )

    assert committed.status_code == 200
    assert first_body["replayed"] is False
    assert [result["revision"] for result in first_body["results"]] == [1, 1]
    assert all(result["changed"] is True for result in first_body["results"])
    assert replayed.status_code == 200
    assert replayed.json() == {**first_body, "replayed": True}
    assert changes_after_replay == changes_after_first
    assert commit_rows == 1

    changed_payload = {
        **payload,
        "operations": [
            {
                **payload["operations"][0],
                "content": {"schemaVersion": 1, "cover": "changed"},
            }
        ],
    }
    key_reused = await client.post(
        "/api/v1/sync/commit",
        json=changed_payload,
        headers=bearer(registered["accessToken"]),
    )
    assert key_reused.status_code == 409
    assert key_reused.json()["error"]["code"] == "sync_idempotency_key_reused"


async def test_sync_commit_rolls_back_the_whole_batch_on_revision_conflict(
    client: AsyncClient,
    db_session: AsyncSession,
) -> None:
    registered = await register(client, "sync-rollback@example.com")
    user_id = UUID(registered["user"]["id"])
    library = LibraryRepository(db_session)
    notebook = await library.create_notebook(
        user_id=user_id,
        notebook_id="rollback-notebook",
        title="Rollback",
        layout_mode="paged",
    )
    page = await library.create_page(
        user_id=user_id,
        notebook_id=notebook.id,
        page_id="rollback-page",
        position=0,
        width=768,
        height=1024,
        coordinate_space_version=1,
    )
    notebook_id = notebook.id
    page_id = page.id
    content = ContentRepository(db_session)
    await content.save_page_content(
        user_id=user_id,
        page_id=page.id,
        base_revision=0,
        content={"strokes": [{"id": "server-stroke"}]},
    )
    await db_session.commit()
    changes = await client.get(
        "/api/v1/sync/changes",
        headers=bearer(registered["accessToken"]),
    )
    before_count = await db_session.scalar(
        select(func.count())
        .select_from(SyncChange)
        .where(SyncChange.user_id == user_id)
    )
    payload = {
        "deviceId": registered["device"]["id"],
        "idempotencyKey": "rollback-batch-1",
        "baseCursor": changes.json()["nextCursor"],
        "operations": [
            {
                "operationId": "would-succeed",
                "operation": "upsert",
                "resourceType": "notebook",
                "resourceId": notebook.id,
                "baseRevision": 0,
                "content": {"cover": "must-rollback"},
            },
            {
                "operationId": "must-conflict",
                "operation": "upsert",
                "resourceType": "page",
                "resourceId": page.id,
                "baseRevision": 0,
                "content": {"strokes": [{"id": "offline-stroke"}]},
            },
        ],
    }

    response = await client.post(
        "/api/v1/sync/commit",
        json=payload,
        headers=bearer(registered["accessToken"]),
    )
    db_session.expire_all()
    stored_notebook = await db_session.scalar(
        select(Notebook).where(
            Notebook.id == notebook_id,
            Notebook.user_id == user_id,
        )
    )
    stored_page = await db_session.scalar(
        select(Page).where(Page.id == page_id, Page.user_id == user_id)
    )
    after_count = await db_session.scalar(
        select(func.count())
        .select_from(SyncChange)
        .where(SyncChange.user_id == user_id)
    )
    commit_rows = await db_session.scalar(
        select(func.count())
        .select_from(SyncCommit)
        .where(SyncCommit.user_id == user_id)
    )

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "sync_revision_conflict"
    assert response.json()["error"]["details"] == {
        "operationId": "must-conflict",
        "resourceType": "page",
        "resourceId": page_id,
        "expectedRevision": 0,
        "currentRevision": 1,
    }
    assert stored_notebook is not None
    assert stored_notebook.revision == 0
    assert stored_notebook.content == {}
    assert stored_page is not None
    assert stored_page.revision == 1
    assert after_count == before_count
    assert commit_rows == 0


async def test_sync_commit_rejects_another_device_id(
    client: AsyncClient,
) -> None:
    registered = await register(client, "sync-device@example.com")
    changes = await client.get(
        "/api/v1/sync/changes",
        headers=bearer(registered["accessToken"]),
    )
    response = await client.post(
        "/api/v1/sync/commit",
        json={
            "deviceId": "11111111-1111-1111-1111-111111111111",
            "idempotencyKey": "wrong-device",
            "baseCursor": changes.json()["nextCursor"],
            "operations": [
                {
                    "operationId": "missing-resource",
                    "operation": "upsert",
                    "resourceType": "notebook",
                    "resourceId": "missing",
                    "baseRevision": 0,
                    "content": {},
                }
            ],
        },
        headers=bearer(registered["accessToken"]),
    )

    assert response.status_code == 403
    assert response.json()["error"]["code"] == "sync_device_mismatch"
