from typing import Any, cast
from uuid import UUID

from conftest import FakeObjectStorage
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.models import Asset, AssetUpload, Notebook

SHA256 = "a" * 64


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


def upload_payload(**overrides: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "notebookId": "notebook-1",
        "assetId": "asset-1",
        "kind": "image",
        "filename": "../../课堂 笔记.png",
        "contentType": "image/png",
        "byteSize": 4,
        "sha256": SHA256,
    }
    payload.update(overrides)
    return payload


async def add_notebook(
    session: AsyncSession, *, user_id: str, notebook_id: str = "notebook-1"
) -> None:
    session.add(
        Notebook(
            id=notebook_id,
            user_id=UUID(user_id),
            title="Test notebook",
            layout_mode="paged",
        )
    )
    await session.commit()


async def test_create_upload_session_is_authenticated_pending_and_idempotent(
    client: AsyncClient,
    db_session: AsyncSession,
    object_storage: FakeObjectStorage,
) -> None:
    unauthorized = await client.post(
        "/api/v1/assets/upload-sessions", json=upload_payload()
    )
    account = await register(client, "asset-owner@example.com")
    await add_notebook(db_session, user_id=account["user"]["id"])

    first = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=bearer(account["accessToken"]),
        json=upload_payload(),
    )
    retry = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=bearer(account["accessToken"]),
        json=upload_payload(),
    )

    assert unauthorized.status_code == 401
    assert first.status_code == 201
    assert retry.status_code == 201
    body = first.json()
    assert body["uploadId"] == retry.json()["uploadId"]
    assert body["status"] == "pending"
    assert body["method"] == "PUT"
    assert body["requiredHeaders"] == {"Content-Type": "image/png"}
    assert body["objectKey"].endswith(
        "/notebooks/notebook-1/images/asset-1/课堂_笔记.png"
    )
    assert len(object_storage.upload_requests) == 2

    upload = await db_session.scalar(select(AssetUpload))
    asset = await db_session.scalar(select(Asset))
    assert upload is not None
    assert upload.status == "pending"
    assert asset is None


async def test_rejects_mismatched_retry_and_invalid_uploads(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    account = await register(client, "validation@example.com")
    await add_notebook(db_session, user_id=account["user"]["id"])
    headers = bearer(account["accessToken"])

    assert (
        await client.post(
            "/api/v1/assets/upload-sessions",
            headers=headers,
            json=upload_payload(),
        )
    ).status_code == 201
    mismatch = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=headers,
        json=upload_payload(filename="different.png"),
    )
    wrong_media = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=headers,
        json=upload_payload(assetId="asset-2", contentType="application/pdf"),
    )
    wrong_extension = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=headers,
        json=upload_payload(assetId="asset-3", filename="note.exe"),
    )
    too_large = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=headers,
        json=upload_payload(assetId="asset-4", byteSize=536_870_913),
    )

    assert mismatch.status_code == 409
    assert mismatch.json()["error"]["code"] == "asset_upload_mismatch"
    assert wrong_media.status_code == 415
    assert wrong_extension.status_code == 415
    assert wrong_extension.json()["error"]["code"] == "unsupported_asset_extension"
    assert too_large.status_code == 413


async def test_upload_session_is_owner_scoped_and_can_be_cancelled(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    owner = await register(client, "owner@example.com")
    stranger = await register(client, "stranger@example.com")
    await add_notebook(db_session, user_id=owner["user"]["id"])

    cross_notebook = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=bearer(stranger["accessToken"]),
        json=upload_payload(),
    )
    created = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=bearer(owner["accessToken"]),
        json=upload_payload(),
    )
    upload_id = created.json()["uploadId"]
    cross_cancel = await client.delete(
        f"/api/v1/assets/upload-sessions/{upload_id}",
        headers=bearer(stranger["accessToken"]),
    )
    cancelled = await client.delete(
        f"/api/v1/assets/upload-sessions/{upload_id}",
        headers=bearer(owner["accessToken"]),
    )
    retry = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=bearer(owner["accessToken"]),
        json=upload_payload(),
    )

    assert cross_notebook.status_code == 404
    assert cross_cancel.status_code == 404
    assert cancelled.status_code == 204
    assert retry.status_code == 409
    assert retry.json()["error"]["code"] == "asset_upload_cancelled"
