from typing import Any, cast
from uuid import UUID

from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.auth.agreements import (
    CURRENT_PRIVACY_POLICY_VERSION,
    CURRENT_TERMS_VERSION,
)
from inknest_server.models import (
    ContentRevision,
    Folder,
    InfiniteCanvas,
    Notebook,
    Page,
    SyncChange,
    SyncCommit,
)


async def _register(client: AsyncClient, email: str) -> dict[str, Any]:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "correct-horse-battery-staple",
            "deviceName": "Merge test device",
            "platform": "ios",
            "privacyPolicyVersion": CURRENT_PRIVACY_POLICY_VERSION,
            "termsVersion": CURRENT_TERMS_VERSION,
        },
    )
    assert response.status_code == 201
    return cast(dict[str, Any], response.json())


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _base_cursor(client: AsyncClient, token: str) -> str:
    response = await client.get(
        "/api/v1/sync/bootstrap",
        headers=_bearer(token),
    )
    assert response.status_code == 200
    return cast(str, response.json()["baseCursor"])


def _merge_payload(
    registered: dict[str, Any],
    *,
    base_cursor: str,
    idempotency_key: str,
    folder_name: str = "Local folder",
) -> dict[str, object]:
    return {
        "deviceId": registered["device"]["id"],
        "idempotencyKey": idempotency_key,
        "baseCursor": base_cursor,
        # Deliberately send the child first. The server creates folders before
        # notebooks while preserving response order.
        "operations": [
            {
                "operationId": "create-notebook",
                "resourceType": "notebook",
                "resourceId": "local-notebook",
                "metadata": {
                    "folderId": "local-folder",
                    "title": "Same title is display data",
                    "layoutMode": "paged",
                    "isArchived": False,
                    "content": {"bookmarkedPageIds": ["page-1"]},
                },
            },
            {
                "operationId": "create-folder",
                "resourceType": "folder",
                "resourceId": "local-folder",
                "metadata": {"name": folder_name},
            },
        ],
    }


async def test_merge_commit_creates_metadata_atomically_and_replays_exactly(
    client: AsyncClient,
    db_session: AsyncSession,
) -> None:
    registered = await _register(client, "merge-create@example.com")
    user_id = UUID(registered["user"]["id"])
    payload = _merge_payload(
        registered,
        base_cursor=await _base_cursor(client, registered["accessToken"]),
        idempotency_key="merge-create-1",
    )

    created = await client.post(
        "/api/v1/sync/merge/commit",
        json=payload,
        headers=_bearer(registered["accessToken"]),
    )
    replayed = await client.post(
        "/api/v1/sync/merge/commit",
        json=payload,
        headers=_bearer(registered["accessToken"]),
    )
    folder = await db_session.scalar(
        select(Folder).where(Folder.id == "local-folder", Folder.user_id == user_id)
    )
    notebook = await db_session.scalar(
        select(Notebook).where(
            Notebook.id == "local-notebook",
            Notebook.user_id == user_id,
        )
    )
    change_count = await db_session.scalar(
        select(func.count())
        .select_from(SyncChange)
        .where(SyncChange.user_id == user_id)
    )
    commit_count = await db_session.scalar(
        select(func.count())
        .select_from(SyncCommit)
        .where(SyncCommit.user_id == user_id)
    )

    assert created.status_code == 200
    assert created.json()["replayed"] is False
    assert [item["resourceType"] for item in created.json()["results"]] == [
        "notebook",
        "folder",
    ]
    assert [item["outcome"] for item in created.json()["results"]] == [
        "applied",
        "applied",
    ]
    assert replayed.status_code == 200
    assert replayed.json() == {**created.json(), "replayed": True}
    assert folder is not None and folder.name == "Local folder"
    assert notebook is not None and notebook.folder_id == "local-folder"
    assert notebook.revision == 1
    assert notebook.content == {"bookmarkedPageIds": ["page-1"]}
    assert change_count == 2
    assert commit_count == 1


async def test_merge_commit_rejects_different_metadata_and_rolls_back_batch(
    client: AsyncClient,
    db_session: AsyncSession,
) -> None:
    registered = await _register(client, "merge-conflict@example.com")
    user_id = UUID(registered["user"]["id"])
    cursor = await _base_cursor(client, registered["accessToken"])
    first_payload = _merge_payload(
        registered,
        base_cursor=cursor,
        idempotency_key="merge-original",
    )
    first = await client.post(
        "/api/v1/sync/merge/commit",
        json=first_payload,
        headers=_bearer(registered["accessToken"]),
    )
    assert first.status_code == 200

    conflicting_payload = {
        **_merge_payload(
            registered,
            base_cursor=cursor,
            idempotency_key="merge-conflicting",
        ),
        "operations": [
            {
                "operationId": "create-rollback-folder",
                "resourceType": "folder",
                "resourceId": "rollback-folder",
                "metadata": {"name": "Must roll back"},
            },
            {
                "operationId": "create-conflicting-notebook",
                "resourceType": "notebook",
                "resourceId": "local-notebook",
                "metadata": {
                    "title": "Different metadata",
                    "layoutMode": "paged",
                },
            },
        ],
    }
    response = await client.post(
        "/api/v1/sync/merge/commit",
        json=conflicting_payload,
        headers=_bearer(registered["accessToken"]),
    )
    rollback_folder = await db_session.scalar(
        select(Folder).where(
            Folder.id == "rollback-folder",
            Folder.user_id == user_id,
        )
    )

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "sync_merge_resource_exists"
    assert rollback_folder is None


async def test_merge_commit_requires_an_owned_parent_folder(
    client: AsyncClient,
) -> None:
    registered = await _register(client, "merge-parent@example.com")
    cursor = await _base_cursor(client, registered["accessToken"])
    payload = {
        "deviceId": registered["device"]["id"],
        "idempotencyKey": "missing-parent",
        "baseCursor": cursor,
        "operations": [
            {
                "operationId": "orphan-notebook",
                "resourceType": "notebook",
                "resourceId": "orphan-notebook",
                "metadata": {
                    "folderId": "missing-folder",
                    "title": "Orphan",
                    "layoutMode": "paged",
                },
            }
        ],
    }

    response = await client.post(
        "/api/v1/sync/merge/commit",
        json=payload,
        headers=_bearer(registered["accessToken"]),
    )

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "sync_merge_parent_not_found"


async def test_merge_commit_creates_page_and_canvas_content_after_parent_notebooks(
    client: AsyncClient,
    db_session: AsyncSession,
) -> None:
    registered = await _register(client, "merge-content@example.com")
    user_id = UUID(registered["user"]["id"])
    cursor = await _base_cursor(client, registered["accessToken"])
    operations = [
        {
            "operationId": "create-page",
            "resourceType": "page",
            "resourceId": "local-page",
            "metadata": {
                "notebookId": "paged-notebook",
                "position": 0,
                "width": 768,
                "height": 1024,
                "coordinateSpaceVersion": {"major": 1},
                "rotationQuarterTurns": 1,
                "template": "grid",
                "content": {"strokes": [{"id": "local-stroke"}]},
            },
        },
        {
            "operationId": "create-canvas",
            "resourceType": "infinite_canvas",
            "resourceId": "local-canvas",
            "metadata": {
                "notebookId": "canvas-notebook",
                "background": "dotted",
                "content": {"nodes": [{"id": "local-node"}]},
            },
        },
        {
            "operationId": "create-paged-notebook",
            "resourceType": "notebook",
            "resourceId": "paged-notebook",
            "metadata": {"title": "Paged", "layoutMode": "paged"},
        },
        {
            "operationId": "create-canvas-notebook",
            "resourceType": "notebook",
            "resourceId": "canvas-notebook",
            "metadata": {
                "title": "Canvas",
                "layoutMode": "infiniteCanvas",
            },
        },
    ]
    payload = {
        "deviceId": registered["device"]["id"],
        "idempotencyKey": "merge-content-1",
        "baseCursor": cursor,
        "operations": operations,
    }

    created = await client.post(
        "/api/v1/sync/merge/commit",
        json=payload,
        headers=_bearer(registered["accessToken"]),
    )
    repeated_with_new_key = await client.post(
        "/api/v1/sync/merge/commit",
        json={**payload, "idempotencyKey": "merge-content-2"},
        headers=_bearer(registered["accessToken"]),
    )
    page = await db_session.scalar(
        select(Page).where(Page.id == "local-page", Page.user_id == user_id)
    )
    canvas = await db_session.scalar(
        select(InfiniteCanvas).where(
            InfiniteCanvas.id == "local-canvas",
            InfiniteCanvas.user_id == user_id,
        )
    )
    revision_count = await db_session.scalar(
        select(func.count())
        .select_from(ContentRevision)
        .where(ContentRevision.user_id == user_id)
    )
    change_count = await db_session.scalar(
        select(func.count())
        .select_from(SyncChange)
        .where(SyncChange.user_id == user_id)
    )

    assert created.status_code == 200
    assert [item["resourceType"] for item in created.json()["results"]] == [
        "page",
        "infinite_canvas",
        "notebook",
        "notebook",
    ]
    assert [item["revision"] for item in created.json()["results"]] == [1, 1, 1, 1]
    assert all(len(item["contentHash"]) == 64 for item in created.json()["results"])
    assert repeated_with_new_key.status_code == 200
    assert [item["outcome"] for item in repeated_with_new_key.json()["results"]] == [
        "unchanged",
        "unchanged",
        "unchanged",
        "unchanged",
    ]
    assert page is not None and page.content == {"strokes": [{"id": "local-stroke"}]}
    assert canvas is not None and canvas.content == {"nodes": [{"id": "local-node"}]}
    assert revision_count == 4
    assert change_count == 4


async def test_merge_commit_rolls_back_content_for_incompatible_notebook_layout(
    client: AsyncClient,
    db_session: AsyncSession,
) -> None:
    registered = await _register(client, "merge-layout@example.com")
    user_id = UUID(registered["user"]["id"])
    payload = {
        "deviceId": registered["device"]["id"],
        "idempotencyKey": "merge-layout-1",
        "baseCursor": await _base_cursor(client, registered["accessToken"]),
        "operations": [
            {
                "operationId": "create-paged-notebook",
                "resourceType": "notebook",
                "resourceId": "paged-only",
                "metadata": {"title": "Paged", "layoutMode": "paged"},
            },
            {
                "operationId": "invalid-canvas",
                "resourceType": "infinite_canvas",
                "resourceId": "invalid-canvas",
                "metadata": {
                    "notebookId": "paged-only",
                    "content": {"nodes": []},
                },
            },
        ],
    }

    response = await client.post(
        "/api/v1/sync/merge/commit",
        json=payload,
        headers=_bearer(registered["accessToken"]),
    )
    notebook = await db_session.scalar(
        select(Notebook).where(
            Notebook.id == "paged-only",
            Notebook.user_id == user_id,
        )
    )

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "sync_merge_parent_incompatible"
    assert notebook is None
