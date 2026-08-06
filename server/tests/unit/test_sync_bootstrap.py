from datetime import UTC, datetime
from typing import Any, cast
from uuid import UUID

from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.config import Settings
from inknest_server.models import SyncChange
from inknest_server.repositories import LibraryRepository
from inknest_server.sync import SyncCursorCodec


async def _register(client: AsyncClient, email: str) -> dict[str, Any]:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "correct-horse-battery-staple",
            "deviceName": "Bootstrap test device",
            "platform": "ios",
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
    await library.create_notebook(
        user_id=first_user_id,
        notebook_id="first-notebook-a",
        title="Same title",
        layout_mode="paged",
    )
    await library.create_notebook(
        user_id=first_user_id,
        notebook_id="first-notebook-b",
        title="Same title",
        layout_mode="paged",
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
    assert body["counts"] == {"folders": 1, "notebooks": 2}
    assert changes_after == changes_before
    assert (
        SyncCursorCodec(test_settings).decode(body["baseCursor"], user_id=first_user_id)
        == 4
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
        "counts": {"folders": 0, "notebooks": 0},
        "baseCursor": response.json()["baseCursor"],
    }
