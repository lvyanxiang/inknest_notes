import hashlib
from typing import Any, cast
from uuid import UUID

from conftest import FakeObjectStorage
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.auth.agreements import (
    CURRENT_PRIVACY_POLICY_VERSION,
    CURRENT_TERMS_VERSION,
)
from inknest_server.models import Asset, AssetUpload, Notebook

CONTENT = b"test"
SHA256 = hashlib.sha256(CONTENT).hexdigest()


async def register(client: AsyncClient, email: str) -> dict[str, Any]:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "correct-horse-battery-staple",
            "deviceName": "Test iPad",
            "platform": "ios",
            "privacyPolicyVersion": CURRENT_PRIVACY_POLICY_VERSION,
            "termsVersion": CURRENT_TERMS_VERSION,
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
        "relativePath": "assets/images/asset-1.png",
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
    assert body["objectKey"].endswith(f"/uploads/{body['uploadId']}/课堂_笔记.png")
    assert len(object_storage.upload_requests) == 2

    upload = await db_session.scalar(select(AssetUpload))
    asset = await db_session.scalar(select(Asset))
    assert upload is not None
    assert upload.status == "pending"
    assert asset is None


async def test_complete_upload_verifies_and_creates_one_ready_asset(
    client: AsyncClient,
    db_session: AsyncSession,
    object_storage: FakeObjectStorage,
) -> None:
    owner = await register(client, "complete-owner@example.com")
    stranger = await register(client, "complete-stranger@example.com")
    await add_notebook(db_session, user_id=owner["user"]["id"])
    created = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=bearer(owner["accessToken"]),
        json=upload_payload(),
    )
    body = created.json()
    object_storage.put_object(
        body["objectKey"],
        CONTENT,
        content_type="image/png",
    )

    pending_download = await client.get(
        "/api/v1/assets/asset-1/download-url",
        headers=bearer(owner["accessToken"]),
    )
    pending_bootstrap = await client.get(
        "/api/v1/sync/bootstrap",
        headers=bearer(owner["accessToken"]),
    )

    cross_user = await client.post(
        f"/api/v1/assets/upload-sessions/{body['uploadId']}/complete",
        headers=bearer(stranger["accessToken"]),
    )
    first = await client.post(
        f"/api/v1/assets/upload-sessions/{body['uploadId']}/complete",
        headers=bearer(owner["accessToken"]),
    )
    retry = await client.post(
        f"/api/v1/assets/upload-sessions/{body['uploadId']}/complete",
        headers=bearer(owner["accessToken"]),
    )
    cross_user_download = await client.get(
        "/api/v1/assets/asset-1/download-url",
        headers=bearer(stranger["accessToken"]),
    )
    download = await client.get(
        "/api/v1/assets/asset-1/download-url",
        headers=bearer(owner["accessToken"]),
    )
    ready_bootstrap = await client.get(
        "/api/v1/sync/bootstrap",
        headers=bearer(owner["accessToken"]),
    )
    stranger_bootstrap = await client.get(
        "/api/v1/sync/bootstrap",
        headers=bearer(stranger["accessToken"]),
    )

    assert cross_user.status_code == 404
    assert pending_download.status_code == 404
    assert pending_bootstrap.status_code == 200
    assert pending_bootstrap.json()["assets"] == []
    assert first.status_code == 200
    assert retry.status_code == 200
    assert first.json() == retry.json()
    assert first.json()["status"] == "ready"
    assert first.json()["assetId"] == "asset-1"
    assert first.json()["byteSize"] == len(CONTENT)
    assert first.json()["sha256"] == SHA256
    assert cross_user_download.status_code == 404
    assert download.status_code == 200
    assert download.json()["method"] == "GET"
    assert download.json()["assetId"] == "asset-1"
    assert download.json()["filename"] == "../../课堂 笔记.png"
    assert download.json()["relativePath"] == "assets/images/asset-1.png"
    assert download.json()["contentType"] == "image/png"
    assert download.json()["byteSize"] == len(CONTENT)
    assert download.json()["sha256"] == SHA256
    assert ready_bootstrap.status_code == 200
    assert [asset["id"] for asset in ready_bootstrap.json()["assets"]] == ["asset-1"]
    assert ready_bootstrap.json()["assets"][0]["notebookId"] == "notebook-1"
    assert (
        ready_bootstrap.json()["assets"][0]["relativePath"]
        == "assets/images/asset-1.png"
    )
    assert ready_bootstrap.json()["assets"][0]["byteSize"] == len(CONTENT)
    assert ready_bootstrap.json()["assets"][0]["sha256"] == SHA256
    assert "objectKey" not in ready_bootstrap.json()["assets"][0]
    assert "downloadUrl" not in ready_bootstrap.json()["assets"][0]
    assert ready_bootstrap.json()["counts"]["assets"] == 1
    assert stranger_bootstrap.status_code == 200
    assert stranger_bootstrap.json()["assets"] == []
    assert len(object_storage.download_requests) == 1

    upload = await db_session.scalar(select(AssetUpload))
    asset = await db_session.scalar(select(Asset))
    assert upload is not None
    assert upload.status == "completed"
    assert upload.completed_at is not None
    assert asset is not None
    assert asset.object_key in object_storage.objects
    assert body["objectKey"] not in object_storage.objects

    object_storage.put_object(
        asset.object_key,
        b"drifted",
        content_type="image/png",
    )
    drifted_object = await client.get(
        "/api/v1/assets/asset-1/download-url",
        headers=bearer(owner["accessToken"]),
    )
    assert drifted_object.status_code == 409
    assert drifted_object.json()["error"]["code"] == "asset_object_metadata_mismatch"

    await object_storage.delete_object(asset.object_key)
    missing_object = await client.get(
        "/api/v1/assets/asset-1/download-url",
        headers=bearer(owner["accessToken"]),
    )
    assert missing_object.status_code == 409
    assert missing_object.json()["error"]["code"] == "asset_object_missing"


async def test_complete_upload_rejects_missing_size_and_hash_mismatches(
    client: AsyncClient,
    db_session: AsyncSession,
    object_storage: FakeObjectStorage,
) -> None:
    owner = await register(client, "verification@example.com")
    await add_notebook(db_session, user_id=owner["user"]["id"])
    headers = bearer(owner["accessToken"])

    missing_session = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=headers,
        json=upload_payload(assetId="missing-asset"),
    )
    missing = await client.post(
        f"/api/v1/assets/upload-sessions/{missing_session.json()['uploadId']}/complete",
        headers=headers,
    )

    size_session = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=headers,
        json=upload_payload(assetId="size-asset"),
    )
    object_storage.put_object(
        size_session.json()["objectKey"],
        b"x",
        content_type="image/png",
    )
    size_mismatch = await client.post(
        f"/api/v1/assets/upload-sessions/{size_session.json()['uploadId']}/complete",
        headers=headers,
    )

    content_type_session = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=headers,
        json=upload_payload(assetId="content-type-asset"),
    )
    object_storage.put_object(
        content_type_session.json()["objectKey"],
        CONTENT,
        content_type="application/octet-stream",
    )
    content_type_mismatch = await client.post(
        f"/api/v1/assets/upload-sessions/"
        f"{content_type_session.json()['uploadId']}/complete",
        headers=headers,
    )

    hash_session = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=headers,
        json=upload_payload(assetId="hash-asset"),
    )
    object_storage.put_object(
        hash_session.json()["objectKey"],
        b"fail",
        content_type="image/png",
    )
    hash_mismatch = await client.post(
        f"/api/v1/assets/upload-sessions/{hash_session.json()['uploadId']}/complete",
        headers=headers,
    )

    assert missing.status_code == 409
    assert missing.json()["error"]["code"] == "asset_upload_object_missing"
    assert size_mismatch.status_code == 422
    assert size_mismatch.json()["error"]["code"] == "asset_upload_size_mismatch"
    assert content_type_mismatch.status_code == 422
    assert (
        content_type_mismatch.json()["error"]["code"]
        == "asset_upload_content_type_mismatch"
    )
    assert hash_mismatch.status_code == 422
    assert hash_mismatch.json()["error"]["code"] == "asset_upload_sha256_mismatch"
    assert await db_session.scalar(select(Asset)) is None


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
    traversal_path = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=headers,
        json=upload_payload(
            assetId="asset-5", relativePath="assets/images/../../outside.png"
        ),
    )
    wrong_kind_path = await client.post(
        "/api/v1/assets/upload-sessions",
        headers=headers,
        json=upload_payload(assetId="asset-6", relativePath="assets/audio/image.png"),
    )

    assert mismatch.status_code == 409
    assert mismatch.json()["error"]["code"] == "asset_upload_mismatch"
    assert wrong_media.status_code == 415
    assert wrong_extension.status_code == 415
    assert wrong_extension.json()["error"]["code"] == "unsupported_asset_extension"
    assert too_large.status_code == 413
    assert traversal_path.status_code == 422
    assert wrong_kind_path.status_code == 422


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
