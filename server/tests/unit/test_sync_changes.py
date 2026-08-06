from typing import Any, cast
from uuid import UUID

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.config import Settings
from inknest_server.models import (
    Conflict,
    Notebook,
    Page,
    SyncChange,
    SyncCommit,
    Tombstone,
    User,
)
from inknest_server.repositories import (
    ContentRepository,
    LibraryRepository,
    LibraryResourceNotFoundError,
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
        params={"cursor": f"x{first_body['nextCursor'][1:]}"},
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


async def test_sync_commit_creates_an_idempotent_page_conflict_copy(
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
                "content": {"cover": "committed-alongside-conflict"},
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

    assert response.status_code == 200
    body = response.json()
    assert [item["outcome"] for item in body["results"]] == ["applied", "conflict"]
    conflict_body = body["results"][1]["conflict"]
    assert conflict_body["resourceType"] == "page"
    assert conflict_body["originalResourceId"] == page_id
    assert conflict_body["copyDisplayName"] == "第 1 页（冲突副本）"
    assert conflict_body["baseRevision"] == 0
    assert conflict_body["currentRevision"] == 1
    assert conflict_body["status"] == "pending"
    assert conflict_body["submittedContent"] == {"strokes": [{"id": "offline-stroke"}]}
    assert conflict_body["currentContent"] == {"strokes": [{"id": "server-stroke"}]}
    assert stored_notebook is not None
    assert stored_notebook.revision == 1
    assert stored_notebook.content == {"cover": "committed-alongside-conflict"}
    assert stored_page is not None
    assert stored_page.revision == 1
    assert stored_page.content == {"strokes": [{"id": "server-stroke"}]}
    assert before_count is not None
    assert after_count is not None
    assert after_count == before_count + 2
    assert commit_rows == 1

    replay = await client.post(
        "/api/v1/sync/commit",
        json=payload,
        headers=bearer(registered["accessToken"]),
    )
    conflict_count = await db_session.scalar(
        select(func.count()).select_from(Conflict).where(Conflict.user_id == user_id)
    )
    change_count_after_replay = await db_session.scalar(
        select(func.count())
        .select_from(SyncChange)
        .where(SyncChange.user_id == user_id)
    )

    assert replay.status_code == 200
    assert replay.json() == {**body, "replayed": True}
    assert conflict_count == 1
    assert change_count_after_replay == after_count

    resolved = await client.post(
        f"/api/v1/sync/conflicts/{conflict_body['id']}/resolve",
        json={"resolution": "keep_both"},
        headers=bearer(registered["accessToken"]),
    )
    db_session.expire_all()
    copied_page = await db_session.scalar(
        select(Page).where(
            Page.id == conflict_body["copyResourceId"],
            Page.user_id == user_id,
        )
    )
    repeated_resolution = await client.post(
        f"/api/v1/sync/conflicts/{conflict_body['id']}/resolve",
        json={"resolution": "keep_both"},
        headers=bearer(registered["accessToken"]),
    )
    changed_resolution = await client.post(
        f"/api/v1/sync/conflicts/{conflict_body['id']}/resolve",
        json={"resolution": "keep_original"},
        headers=bearer(registered["accessToken"]),
    )

    assert resolved.status_code == 200
    assert resolved.json()["status"] == "resolved"
    assert resolved.json()["resolution"] == "keep_both"
    assert copied_page is not None
    assert copied_page.conflict_of == page_id
    assert copied_page.position == 1
    assert copied_page.revision == 1
    assert copied_page.content == {"strokes": [{"id": "offline-stroke"}]}
    assert repeated_resolution.status_code == 200
    assert changed_resolution.status_code == 409
    assert (
        changed_resolution.json()["error"]["code"] == "sync_conflict_already_resolved"
    )


async def test_notebook_conflicts_support_keep_both_and_use_conflict(
    client: AsyncClient,
    db_session: AsyncSession,
) -> None:
    registered = await register(client, "notebook-conflicts@example.com")
    user_id = UUID(registered["user"]["id"])
    library = LibraryRepository(db_session)
    keep_both_notebook = await library.create_notebook(
        user_id=user_id,
        notebook_id="notebook-keep-both",
        title="A" * 300,
        layout_mode="paged",
    )
    use_conflict_notebook = await library.create_notebook(
        user_id=user_id,
        notebook_id="notebook-use-conflict",
        title="Study Notes",
        layout_mode="paged",
    )
    keep_original_notebook = await library.create_notebook(
        user_id=user_id,
        notebook_id="notebook-keep-original",
        title="Keep Original",
        layout_mode="paged",
    )
    keep_both_notebook_id = keep_both_notebook.id
    use_conflict_notebook_id = use_conflict_notebook.id
    keep_original_notebook_id = keep_original_notebook.id
    content = ContentRepository(db_session)
    for notebook in (
        keep_both_notebook,
        use_conflict_notebook,
        keep_original_notebook,
    ):
        await content.save_notebook_content(
            user_id=user_id,
            notebook_id=notebook.id,
            base_revision=0,
            content={"source": "server", "notebookId": notebook.id},
        )
    await db_session.commit()

    async def create_conflict(
        *, notebook_id: str, idempotency_key: str
    ) -> dict[str, Any]:
        changes = await client.get(
            "/api/v1/sync/changes",
            headers=bearer(registered["accessToken"]),
        )
        response = await client.post(
            "/api/v1/sync/commit",
            json={
                "deviceId": registered["device"]["id"],
                "idempotencyKey": idempotency_key,
                "baseCursor": changes.json()["nextCursor"],
                "operations": [
                    {
                        "operationId": idempotency_key,
                        "operation": "upsert",
                        "resourceType": "notebook",
                        "resourceId": notebook_id,
                        "baseRevision": 0,
                        "content": {
                            "source": "offline-device",
                            "notebookId": notebook_id,
                        },
                    }
                ],
            },
            headers=bearer(registered["accessToken"]),
        )
        assert response.status_code == 200
        result = cast(dict[str, Any], response.json()["results"][0])
        assert result["outcome"] == "conflict"
        return cast(dict[str, Any], result["conflict"])

    keep_both_conflict = await create_conflict(
        notebook_id=keep_both_notebook_id,
        idempotency_key="notebook-keep-both-conflict",
    )
    assert len(keep_both_conflict["copyDisplayName"]) == 300
    assert keep_both_conflict["copyDisplayName"].endswith("（冲突副本）")
    kept_both = await client.post(
        f"/api/v1/sync/conflicts/{keep_both_conflict['id']}/resolve",
        json={"resolution": "keep_both"},
        headers=bearer(registered["accessToken"]),
    )

    use_conflict = await create_conflict(
        notebook_id=use_conflict_notebook_id,
        idempotency_key="notebook-use-conflict-version",
    )
    replaced = await client.post(
        f"/api/v1/sync/conflicts/{use_conflict['id']}/resolve",
        json={"resolution": "use_conflict"},
        headers=bearer(registered["accessToken"]),
    )
    keep_original = await create_conflict(
        notebook_id=keep_original_notebook_id,
        idempotency_key="notebook-keep-original-version",
    )
    kept_original = await client.post(
        f"/api/v1/sync/conflicts/{keep_original['id']}/resolve",
        json={"resolution": "keep_original"},
        headers=bearer(registered["accessToken"]),
    )
    db_session.expire_all()
    notebook_copy = await db_session.scalar(
        select(Notebook).where(
            Notebook.id == keep_both_conflict["copyResourceId"],
            Notebook.user_id == user_id,
        )
    )
    replaced_original = await db_session.scalar(
        select(Notebook).where(
            Notebook.id == use_conflict_notebook_id,
            Notebook.user_id == user_id,
        )
    )
    unmaterialized_copy = await db_session.scalar(
        select(Notebook).where(
            Notebook.id == use_conflict["copyResourceId"],
            Notebook.user_id == user_id,
        )
    )
    unchanged_original = await db_session.scalar(
        select(Notebook).where(
            Notebook.id == keep_original_notebook_id,
            Notebook.user_id == user_id,
        )
    )
    kept_original_copy = await db_session.scalar(
        select(Notebook).where(
            Notebook.id == keep_original["copyResourceId"],
            Notebook.user_id == user_id,
        )
    )

    assert kept_both.status_code == 200
    assert notebook_copy is not None
    assert notebook_copy.conflict_of == keep_both_notebook_id
    assert notebook_copy.title.endswith("（冲突副本）")
    assert len(notebook_copy.title) == 300
    assert notebook_copy.content["source"] == "offline-device"
    assert replaced.status_code == 200
    assert replaced_original is not None
    assert replaced_original.revision == 2
    assert replaced_original.content["source"] == "offline-device"
    assert unmaterialized_copy is None
    assert kept_original.status_code == 200
    assert kept_original.json()["resolution"] == "keep_original"
    assert unchanged_original is not None
    assert unchanged_original.revision == 1
    assert unchanged_original.content["source"] == "server"
    assert kept_original_copy is None


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


async def test_sync_delete_is_soft_and_restorable(
    client: AsyncClient,
    db_session: AsyncSession,
) -> None:
    registered = await register(client, "sync-delete-restore@example.com")
    user_id = UUID(registered["user"]["id"])
    notebook = await LibraryRepository(db_session).create_notebook(
        user_id=user_id,
        notebook_id="delete-restore-notebook",
        title="Recover me",
        layout_mode="paged",
    )
    await ContentRepository(db_session).save_notebook_content(
        user_id=user_id,
        notebook_id=notebook.id,
        base_revision=0,
        content={"blocks": [{"id": "kept"}]},
    )
    notebook_id = notebook.id
    await db_session.commit()
    changes = await client.get(
        "/api/v1/sync/changes",
        headers=bearer(registered["accessToken"]),
    )
    payload = {
        "deviceId": registered["device"]["id"],
        "idempotencyKey": "delete-restore-1",
        "baseCursor": changes.json()["nextCursor"],
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

    deleted = await client.post(
        "/api/v1/sync/commit",
        json=payload,
        headers=bearer(registered["accessToken"]),
    )
    body = deleted.json()
    replayed = await client.post(
        "/api/v1/sync/commit",
        json=payload,
        headers=bearer(registered["accessToken"]),
    )
    db_session.expire_all()
    stored = await db_session.scalar(
        select(Notebook).where(Notebook.id == notebook_id, Notebook.user_id == user_id)
    )
    with pytest.raises(LibraryResourceNotFoundError):
        await LibraryRepository(db_session).get_notebook(
            user_id=user_id,
            notebook_id=notebook_id,
        )

    assert deleted.status_code == 200
    assert body["results"][0]["outcome"] == "deleted"
    assert body["results"][0]["revision"] == 2
    assert body["results"][0]["tombstone"]["state"] == "active"
    assert replayed.json() == {**body, "replayed": True}
    assert stored is not None
    assert stored.deleted_at is not None
    assert stored.content == {"blocks": [{"id": "kept"}]}

    restored = await client.post(
        f"/api/v1/sync/tombstones/{body['results'][0]['tombstone']['id']}/restore",
        headers=bearer(registered["accessToken"]),
    )
    db_session.expire_all()
    recovered = await LibraryRepository(db_session).get_notebook(
        user_id=user_id,
        notebook_id=notebook_id,
    )

    assert restored.status_code == 200
    assert restored.json()["state"] == "restored"
    assert restored.json()["resolution"] == "restored_snapshot"
    assert recovered is not None
    assert recovered.revision == 3
    assert recovered.deleted_at is None
    assert recovered.content == {"blocks": [{"id": "kept"}]}


async def test_delete_edit_races_always_preserve_the_edit(
    client: AsyncClient,
    db_session: AsyncSession,
) -> None:
    registered = await register(client, "sync-delete-edit@example.com")
    user_id = UUID(registered["user"]["id"])
    library = LibraryRepository(db_session)
    delete_first = await library.create_notebook(
        user_id=user_id,
        notebook_id="delete-first",
        title="Delete first",
        layout_mode="paged",
    )
    edit_first = await library.create_notebook(
        user_id=user_id,
        notebook_id="edit-first",
        title="Edit first",
        layout_mode="paged",
    )
    content = ContentRepository(db_session)
    for notebook in (delete_first, edit_first):
        await content.save_notebook_content(
            user_id=user_id,
            notebook_id=notebook.id,
            base_revision=0,
            content={"value": "base"},
        )
    await db_session.commit()
    cursor_response = await client.get(
        "/api/v1/sync/changes",
        headers=bearer(registered["accessToken"]),
    )
    base_cursor = cursor_response.json()["nextCursor"]

    async def commit(
        *, key: str, operation: str, resource_id: str, content_value: str | None = None
    ) -> dict[str, Any]:
        item: dict[str, Any] = {
            "operationId": key,
            "operation": operation,
            "resourceType": "notebook",
            "resourceId": resource_id,
            "baseRevision": 1,
        }
        if content_value is not None:
            item["content"] = {"value": content_value}
        response = await client.post(
            "/api/v1/sync/commit",
            json={
                "deviceId": registered["device"]["id"],
                "idempotencyKey": key,
                "baseCursor": base_cursor,
                "operations": [item],
            },
            headers=bearer(registered["accessToken"]),
        )
        assert response.status_code == 200
        return cast(dict[str, Any], response.json()["results"][0])

    await commit(
        key="delete-first-delete", operation="delete", resource_id="delete-first"
    )
    edit_after_delete = await commit(
        key="delete-first-edit",
        operation="upsert",
        resource_id="delete-first",
        content_value="offline edit",
    )
    await commit(
        key="edit-first-edit",
        operation="upsert",
        resource_id="edit-first",
        content_value="newer edit",
    )
    delete_after_edit = await commit(
        key="edit-first-delete",
        operation="delete",
        resource_id="edit-first",
    )
    db_session.expire_all()
    resources = list(
        await db_session.scalars(
            select(Notebook).where(
                Notebook.user_id == user_id,
                Notebook.id.in_(["delete-first", "edit-first"]),
            )
        )
    )
    tombstones = list(
        await db_session.scalars(select(Tombstone).where(Tombstone.user_id == user_id))
    )

    assert edit_after_delete["outcome"] == "delete_conflict"
    assert edit_after_delete["tombstone"]["conflictKind"] == "edit_after_delete"
    assert delete_after_edit["outcome"] == "delete_conflict"
    assert delete_after_edit["tombstone"]["conflictKind"] == "delete_after_edit"
    assert {item.id: item.content for item in resources} == {
        "delete-first": {"value": "offline edit"},
        "edit-first": {"value": "newer edit"},
    }
    assert all(item.deleted_at is None for item in resources)
    assert len(tombstones) == 2
    assert all(item.state == "restored" for item in tombstones)
    assert all(item.resolution == "preserved_edit" for item in tombstones)


async def test_sync_soft_delete_supports_pages_and_infinite_canvases(
    client: AsyncClient,
    db_session: AsyncSession,
) -> None:
    registered = await register(client, "sync-delete-layouts@example.com")
    user_id = UUID(registered["user"]["id"])
    library = LibraryRepository(db_session)
    paged = await library.create_notebook(
        user_id=user_id,
        notebook_id="delete-page-parent",
        title="Paged",
        layout_mode="paged",
    )
    page = await library.create_page(
        user_id=user_id,
        notebook_id=paged.id,
        page_id="delete-page",
        position=0,
        width=768,
        height=1024,
        coordinate_space_version=1,
    )
    infinite = await library.create_notebook(
        user_id=user_id,
        notebook_id="delete-canvas-parent",
        title="Infinite",
        layout_mode="infiniteCanvas",
    )
    canvas = await library.create_infinite_canvas(
        user_id=user_id,
        notebook_id=infinite.id,
        canvas_id="delete-canvas",
    )
    content = ContentRepository(db_session)
    await content.save_page_content(
        user_id=user_id,
        page_id=page.id,
        base_revision=0,
        content={"strokes": []},
    )
    await content.save_infinite_canvas_content(
        user_id=user_id,
        canvas_id=canvas.id,
        base_revision=0,
        content={"nodes": []},
    )
    page_id = page.id
    canvas_id = canvas.id
    await db_session.commit()
    changes = await client.get(
        "/api/v1/sync/changes",
        headers=bearer(registered["accessToken"]),
    )

    response = await client.post(
        "/api/v1/sync/commit",
        json={
            "deviceId": registered["device"]["id"],
            "idempotencyKey": "delete-page-and-canvas",
            "baseCursor": changes.json()["nextCursor"],
            "operations": [
                {
                    "operationId": "delete-page",
                    "operation": "delete",
                    "resourceType": "page",
                    "resourceId": page_id,
                    "baseRevision": 1,
                },
                {
                    "operationId": "delete-canvas",
                    "operation": "delete",
                    "resourceType": "infinite_canvas",
                    "resourceId": canvas_id,
                    "baseRevision": 1,
                },
            ],
        },
        headers=bearer(registered["accessToken"]),
    )

    assert response.status_code == 200
    assert [item["outcome"] for item in response.json()["results"]] == [
        "deleted",
        "deleted",
    ]
    assert [
        item["tombstone"]["resourceType"] for item in response.json()["results"]
    ] == ["page", "infinite_canvas"]
