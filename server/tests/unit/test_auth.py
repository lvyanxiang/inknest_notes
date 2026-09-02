from typing import Any
from uuid import UUID

from httpx import AsyncClient, Response
from sqlalchemy import select

from inknest_server.auth.agreements import (
    CURRENT_PRIVACY_POLICY_VERSION,
    CURRENT_TERMS_VERSION,
)
from inknest_server.auth.passwords import PasswordManager
from inknest_server.auth.rate_limit import LoginRateLimiter
from inknest_server.auth.service import AuthService
from inknest_server.auth.tokens import TokenManager
from inknest_server.config import Settings
from inknest_server.models import AccountDeletionRequest, Device, RefreshToken, User


def registration_payload(
    email: str = "writer@example.com",
    *,
    device_name: str = "My iPad",
    client_instance_id: str | None = None,
) -> dict[str, str]:
    instance_id = (
        client_instance_id or f"install-{device_name.lower().replace(' ', '-')}"
    )
    return {
        "email": email,
        "password": "correct-horse-battery-staple",
        "deviceName": device_name,
        "platform": "ios",
        "clientInstanceId": instance_id,
        "privacyPolicyVersion": CURRENT_PRIVACY_POLICY_VERSION,
        "termsVersion": CURRENT_TERMS_VERSION,
    }


async def register(
    client: AsyncClient,
    email: str = "writer@example.com",
    *,
    device_name: str = "My iPad",
) -> Response:
    return await client.post(
        "/api/v1/auth/register",
        json=registration_payload(email, device_name=device_name),
    )


def bearer(access_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {access_token}"}


async def test_register_and_read_current_user(client: AsyncClient) -> None:
    response = await register(client, "Writer@Example.com")

    body: dict[str, Any] = response.json()
    assert response.status_code == 201
    assert body["tokenType"] == "bearer"
    assert body["expiresIn"] == 900
    assert body["user"]["email"] == "writer@example.com"
    assert body["user"]["privacyPolicyVersion"] == CURRENT_PRIVACY_POLICY_VERSION
    assert body["user"]["termsVersion"] == CURRENT_TERMS_VERSION
    assert body["device"]["current"] is True

    me_response = await client.get(
        "/api/v1/me",
        headers=bearer(body["accessToken"]),
    )
    assert me_response.status_code == 200
    assert me_response.json()["id"] == body["user"]["id"]


async def test_duplicate_registration_and_invalid_login_are_rejected(
    client: AsyncClient,
) -> None:
    first = await register(client)
    duplicate = await register(client, "WRITER@example.com")
    bad_login_payload = registration_payload()
    bad_login_payload["password"] = "wrong-password"
    bad_login = await client.post("/api/v1/auth/login", json=bad_login_payload)

    assert first.status_code == 201
    assert duplicate.status_code == 409
    assert duplicate.json()["error"]["code"] == "email_already_registered"
    assert bad_login.status_code == 401
    assert bad_login.json()["error"]["code"] == "invalid_credentials"


async def test_login_creates_a_separate_device_session(client: AsyncClient) -> None:
    assert (await register(client)).status_code == 201
    login_payload = registration_payload(device_name="My Phone")
    login = await client.post("/api/v1/auth/login", json=login_payload)

    assert login.status_code == 200
    assert login.json()["device"]["name"] == "My Phone"

    devices = await client.get(
        "/api/v1/devices",
        headers=bearer(login.json()["accessToken"]),
    )
    assert devices.status_code == 200
    assert {device["name"] for device in devices.json()} == {
        "My iPad",
        "My Phone",
    }


async def test_login_reuses_the_same_installation_device(client: AsyncClient) -> None:
    registered = await register(client)
    original_device_id = registered.json()["device"]["id"]
    same_installation = await client.post(
        "/api/v1/auth/login",
        json=registration_payload(
            device_name="My iPad renamed",
            client_instance_id="install-my-ipad",
        ),
    )
    assert same_installation.status_code == 200
    assert same_installation.json()["device"]["id"] == original_device_id

    devices = await client.get(
        "/api/v1/devices",
        headers=bearer(same_installation.json()["accessToken"]),
    )
    assert devices.status_code == 200
    assert len(devices.json()) == 1
    assert devices.json()[0]["name"] == "My iPad renamed"


async def test_failed_logins_are_rate_limited(client: AsyncClient) -> None:
    assert (await register(client)).status_code == 201
    payload = registration_payload()
    payload["password"] = "wrong-password"

    first = await client.post("/api/v1/auth/login", json=payload)
    second = await client.post("/api/v1/auth/login", json=payload)
    limited = await client.post("/api/v1/auth/login", json=payload)

    assert first.status_code == 401
    assert second.status_code == 401
    assert limited.status_code == 429
    assert limited.headers["retry-after"] == "60"
    assert limited.json()["error"]["code"] == "login_rate_limited"
    assert limited.json()["error"]["details"] == {"retryAfterSeconds": 60}


async def test_successful_login_clears_account_client_failures(
    client: AsyncClient,
) -> None:
    assert (await register(client)).status_code == 201
    wrong_payload = registration_payload()
    wrong_payload["password"] = "wrong-password"

    assert (
        await client.post("/api/v1/auth/login", json=wrong_payload)
    ).status_code == 401
    assert (
        await client.post("/api/v1/auth/login", json=registration_payload())
    ).status_code == 200
    assert (
        await client.post("/api/v1/auth/login", json=wrong_payload)
    ).status_code == 401
    assert (
        await client.post("/api/v1/auth/login", json=wrong_payload)
    ).status_code == 401
    limited = await client.post("/api/v1/auth/login", json=wrong_payload)

    assert limited.status_code == 429


async def test_refresh_rotates_token_and_reuse_revokes_family(
    client: AsyncClient,
) -> None:
    registered = await register(client)
    old_token = registered.json()["refreshToken"]

    refreshed = await client.post(
        "/api/v1/auth/refresh",
        json={"refreshToken": old_token},
    )
    new_token = refreshed.json()["refreshToken"]
    reused = await client.post(
        "/api/v1/auth/refresh",
        json={"refreshToken": old_token},
    )
    family_revoked = await client.post(
        "/api/v1/auth/refresh",
        json={"refreshToken": new_token},
    )

    assert refreshed.status_code == 200
    assert new_token != old_token
    assert reused.status_code == 401
    assert reused.json()["error"]["code"] == "refresh_token_reused"
    assert family_revoked.status_code == 401


async def test_logout_revokes_refresh_token(client: AsyncClient) -> None:
    registered = await register(client)
    refresh_token = registered.json()["refreshToken"]

    logout = await client.post(
        "/api/v1/auth/logout",
        json={"refreshToken": refresh_token},
    )
    refresh = await client.post(
        "/api/v1/auth/refresh",
        json={"refreshToken": refresh_token},
    )

    assert logout.status_code == 204
    assert refresh.status_code == 401


async def test_device_revoke_is_user_scoped_and_invalidates_access(
    client: AsyncClient,
) -> None:
    first = await register(client, "first@example.com", device_name="First iPad")
    second = await register(client, "second@example.com", device_name="Second iPad")
    first_body = first.json()
    second_body = second.json()

    cross_user = await client.delete(
        f"/api/v1/devices/{second_body['device']['id']}",
        headers=bearer(first_body["accessToken"]),
    )
    revoke_own = await client.delete(
        f"/api/v1/devices/{first_body['device']['id']}",
        headers=bearer(first_body["accessToken"]),
    )
    after_revoke = await client.get(
        "/api/v1/me",
        headers=bearer(first_body["accessToken"]),
    )
    refresh_after_revoke = await client.post(
        "/api/v1/auth/refresh",
        json={"refreshToken": first_body["refreshToken"]},
    )
    second_still_valid = await client.get(
        "/api/v1/me",
        headers=bearer(second_body["accessToken"]),
    )

    assert cross_user.status_code == 404
    assert revoke_own.status_code == 204
    assert after_revoke.status_code == 401
    assert refresh_after_revoke.status_code == 401
    assert second_still_valid.status_code == 200


async def test_registration_rejects_missing_or_stale_agreements(
    client: AsyncClient,
) -> None:
    missing = registration_payload("missing@example.com")
    missing.pop("privacyPolicyVersion")
    stale = registration_payload("stale@example.com")
    stale["termsVersion"] = "2025-01-01"

    missing_response = await client.post("/api/v1/auth/register", json=missing)
    stale_response = await client.post("/api/v1/auth/register", json=stale)

    assert missing_response.status_code == 422
    assert stale_response.status_code == 409
    assert stale_response.json()["error"]["code"] == "agreement_version_outdated"


async def test_existing_account_can_accept_current_agreements(
    client: AsyncClient, db_session: Any
) -> None:
    registered = await register(client, "legacy@example.com")
    user = await db_session.get(User, UUID(registered.json()["user"]["id"]))
    assert user is not None
    user.privacy_policy_version = None
    user.terms_version = None
    user.agreements_accepted_at = None
    await db_session.commit()

    accepted = await client.put(
        "/api/v1/me/agreements",
        headers=bearer(registered.json()["accessToken"]),
        json={
            "privacyPolicyVersion": CURRENT_PRIVACY_POLICY_VERSION,
            "termsVersion": CURRENT_TERMS_VERSION,
        },
    )

    assert accepted.status_code == 200
    assert accepted.json()["agreementsAcceptedAt"] is not None


async def test_password_change_revokes_other_devices(client: AsyncClient) -> None:
    first = await register(client, "password@example.com", device_name="First iPad")
    second = await client.post(
        "/api/v1/auth/login",
        json=registration_payload("password@example.com", device_name="Second iPad"),
    )

    changed = await client.put(
        "/api/v1/me/password",
        headers=bearer(second.json()["accessToken"]),
        json={
            "currentPassword": "correct-horse-battery-staple",
            "newPassword": "new-correct-horse-battery-staple",
        },
    )
    first_after = await client.get(
        "/api/v1/me", headers=bearer(first.json()["accessToken"])
    )
    second_after = await client.get(
        "/api/v1/me", headers=bearer(second.json()["accessToken"])
    )

    assert changed.status_code == 204
    assert first_after.status_code == 401
    assert second_after.status_code == 200


async def test_account_deletion_removes_cloud_rows_and_objects(
    client: AsyncClient, db_session: Any, object_storage: Any
) -> None:
    registered = await register(client, "delete@example.com")
    body = registered.json()
    user_id = body["user"]["id"]
    object_key = f"users/{user_id}/notebooks/note/images/asset/file.png"
    object_storage.put_object(object_key, b"private", content_type="image/png")

    deleted = await client.request(
        "DELETE",
        "/api/v1/me",
        headers=bearer(body["accessToken"]),
        json={
            "password": "correct-horse-battery-staple",
            "confirmation": "DELETE",
        },
    )
    after = await client.get("/api/v1/me", headers=bearer(body["accessToken"]))

    assert deleted.status_code == 202
    assert deleted.json() == {
        "status": "completed",
        "cloudDeletionComplete": True,
        "localDataRetained": True,
    }
    assert after.status_code == 401
    assert object_key not in object_storage.objects
    db_session.expire_all()
    assert await db_session.get(User, UUID(user_id)) is None
    request = await db_session.scalar(
        select(AccountDeletionRequest).where(
            AccountDeletionRequest.user_id == UUID(user_id)
        )
    )
    assert request is not None
    assert request.status == "completed"
    assert list(await db_session.scalars(select(Device))) == []
    assert list(await db_session.scalars(select(RefreshToken))) == []


async def test_account_deletion_failure_is_pending_and_retryable(
    client: AsyncClient,
    db_session: Any,
    object_storage: Any,
    test_settings: Settings,
) -> None:
    registered = await register(client, "retry-delete@example.com")
    body = registered.json()
    user_id = UUID(body["user"]["id"])
    object_key = f"users/{user_id}/notebooks/note/files/asset.pdf"
    object_storage.put_object(object_key, b"private", content_type="application/pdf")
    object_storage.delete_failures.add(object_key)

    accepted = await client.request(
        "DELETE",
        "/api/v1/me",
        headers=bearer(body["accessToken"]),
        json={
            "password": "correct-horse-battery-staple",
            "confirmation": "DELETE",
        },
    )

    assert accepted.status_code == 202
    assert accepted.json()["status"] == "pending"
    assert accepted.json()["cloudDeletionComplete"] is False
    assert (
        await client.get("/api/v1/me", headers=bearer(body["accessToken"]))
    ).status_code == 401
    request = await db_session.scalar(
        select(AccountDeletionRequest).where(AccountDeletionRequest.user_id == user_id)
    )
    assert request is not None
    assert request.object_keys == [object_key]
    assert request.last_error == "RuntimeError"

    object_storage.delete_failures.clear()
    service = AuthService(
        db_session,
        PasswordManager(),
        TokenManager(test_settings),
        LoginRateLimiter.from_settings(test_settings),
        object_storage,
    )
    assert await service.retry_pending_account_deletions() == (1, 0)
    db_session.expire_all()
    assert await db_session.get(User, user_id) is None
    assert object_key not in object_storage.objects
