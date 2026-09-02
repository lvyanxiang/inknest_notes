from datetime import UTC, datetime
from typing import Any, cast
from uuid import UUID

from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.auth.agreements import (
    CURRENT_PRIVACY_POLICY_VERSION,
    CURRENT_TERMS_VERSION,
)
from inknest_server.config import Settings
from inknest_server.models import SyncChange
from inknest_server.repositories import ContentRepository, LibraryRepository
from inknest_server.sync import SyncCursorCodec


async def _register(client: AsyncClient, email: str) -> dict[str, Any]:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "correct-horse-battery-staple",
            "deviceName": "Bootstrap test device",
            "platform": "ios",
            "privacyPolicyVersion": CURRENT_PRIVACY_POLICY_VERSION,
            "termsVersion": CURRENT_TERMS_VERSION,
        },
    )
    assert response.status_code == 201
    return cast(dict[str, Any], response.json())


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def test_bootstrap_inventory_is_read_only_active_and_account_scoped(
    client: AsyncClient,
    db_session: AsyncSession,
    test_settings: Settings,
) -> None:
    first = await _register(client, "bootstrap-first@example.com")
    second = await _register(client, "bootstrap-second@example.com")
    first_user_id = UUID(first["user"]["id"])
    second_user_id = UUID(second["user"]["id"])
    library = LibraryRepository(db_session)

    await library.create_folder(
        user_id=first_user_id,
        folder_id="first-folder",
        name="Shared title",
    )
    paged_notebook = await library.create_notebook(
        user_id=first_user_id,
        notebook_id="first-notebook-a",
        title="Same title",
        layout_mode="paged",
    )
    canvas_notebook = await library.create_notebook(
        user_id=first_user_id,
        notebook_id="first-notebook-b",
        title="Same title",
        layout_mode="infiniteCanvas",
    )
    page = await library.create_page(
        user_id=first_user_id,
        notebook_id=paged_notebook.id,
        page_id="first-page",
        position=0,
        width=768,
        height=1024,
        coordinate_space_version=1,
        template="ruled",
    )
    canvas = await library.create_infinite_canvas(
        user_id=first_user_id,
        notebook_id=canvas_notebook.id,
        canvas_id="first-canvas",
        background="grid",
    )
    content = ContentRepository(db_session)
    await content.save_page_content(
        user_id=first_user_id,
        page_id=page.id,
        base_revision=0,
        content={"strokes": [{"id": "stroke-1"}]},
    )
    await content.save_infinite_canvas_content(
        user_id=first_user_id,
        canvas_id=canvas.id,
        base_revision=0,
        content={"nodes": [{"id": "node-1"}]},
    )
    await library.create_asset_metadata(
        user_id=first_user_id,
        notebook_id=paged_notebook.id,
        asset_id="first-asset",
        kind="image",
        original_filename="diagram.png",
        relative_path="assets/images/diagram.png",
        object_key=(
            f"users/{first_user_id}/notebooks/{paged_notebook.id}/"
            "images/first-asset/diagram.png"
        ),
        content_type="image/png",
        byte_size=4,
        sha256="0" * 64,
    )
    deleted = await library.create_notebook(
        user_id=first_user_id,
        notebook_id="first-deleted",
        title="Deleted",
        layout_mode="paged",
    )
    deleted.deleted_at = datetime.now(UTC)
    await library.create_notebook(
        user_id=second_user_id,
        notebook_id="second-private",
        title="Private",
        layout_mode="paged",
    )
    await db_session.commit()
    changes_before = await db_session.scalar(
        select(func.count()).select_from(SyncChange)
    )

    unauthorized = await client.get("/api/v1/sync/bootstrap")
    response = await client.get(
        "/api/v1/sync/bootstrap",
        headers=_bearer(first["accessToken"]),
    )
    body = response.json()
    changes_after = await db_session.scalar(
        select(func.count()).select_from(SyncChange)
    )

    assert unauthorized.status_code == 401
    assert response.status_code == 200
    assert body["hasCloudLibrary"] is True
    assert body["folderIds"] == ["first-folder"]
    assert body["notebookIds"] == ["first-notebook-a", "first-notebook-b"]
    assert [item["id"] for item in body["folders"]] == ["first-folder"]
    assert body["folders"][0]["name"] == "Shared title"
    assert body["folders"][0]["revision"] == 0
    assert body["folders"][0]["contentHash"] == ""
    assert [item["id"] for item in body["notebooks"]] == [
        "first-notebook-a",
        "first-notebook-b",
    ]
    assert all(item["title"] == "Same title" for item in body["notebooks"])
    assert all(item["createdAt"] for item in body["notebooks"])
    assert [item["id"] for item in body["pages"]] == ["first-page"]
    assert body["pages"][0]["content"] == {"strokes": [{"id": "stroke-1"}]}
    assert body["pages"][0]["coordinateSpaceVersion"] == 1
    assert [item["id"] for item in body["infiniteCanvases"]] == ["first-canvas"]
    assert body["infiniteCanvases"][0]["content"] == {"nodes": [{"id": "node-1"}]}
    assert [item["id"] for item in body["assets"]] == ["first-asset"]
    assert body["assets"][0]["notebookId"] == "first-notebook-a"
    assert body["assets"][0]["originalFilename"] == "diagram.png"
    assert body["assets"][0]["sha256"] == "0" * 64
    assert body["counts"] == {
        "folders": 1,
        "notebooks": 2,
        "pages": 1,
        "infiniteCanvases": 1,
        "assets": 1,
    }
    assert changes_after == changes_before
    assert (
        SyncCursorCodec(test_settings).decode(body["baseCursor"], user_id=first_user_id)
        == 9
    )


async def test_bootstrap_inventory_reports_an_empty_cloud_library(
    client: AsyncClient,
) -> None:
    registered = await _register(client, "bootstrap-empty@example.com")

    response = await client.get(
        "/api/v1/sync/bootstrap",
        headers=_bearer(registered["accessToken"]),
    )

    assert response.status_code == 200
    assert response.json() == {
        "hasCloudLibrary": False,
        "folderIds": [],
        "notebookIds": [],
        "folders": [],
        "notebooks": [],
        "pages": [],
        "infiniteCanvases": [],
        "assets": [],
        "counts": {
            "folders": 0,
            "notebooks": 0,
            "pages": 0,
            "infiniteCanvases": 0,
            "assets": 0,
        },
        "baseCursor": response.json()["baseCursor"],
    }
