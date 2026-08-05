from typing import Any

from httpx import AsyncClient, Response


def registration_payload(
    email: str = "writer@example.com",
    *,
    device_name: str = "My iPad",
) -> dict[str, str]:
    return {
        "email": email,
        "password": "correct-horse-battery-staple",
        "deviceName": device_name,
        "platform": "ios",
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
