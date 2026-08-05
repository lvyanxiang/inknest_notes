from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from hashlib import sha256
from secrets import token_urlsafe
from typing import Any
from uuid import UUID

import jwt

from inknest_server.config import Settings


class InvalidAccessTokenError(Exception):
    pass


@dataclass(frozen=True)
class AccessTokenClaims:
    user_id: UUID
    device_id: UUID


class TokenManager:
    def __init__(self, settings: Settings) -> None:
        self._secret = settings.jwt_secret.get_secret_value()
        self._issuer = settings.jwt_issuer
        self._access_token_minutes = settings.access_token_minutes
        self._refresh_token_days = settings.refresh_token_days

    @property
    def access_token_seconds(self) -> int:
        return self._access_token_minutes * 60

    def create_access_token(self, *, user_id: UUID, device_id: UUID) -> str:
        now = datetime.now(UTC)
        payload: dict[str, Any] = {
            "sub": str(user_id),
            "deviceId": str(device_id),
            "iss": self._issuer,
            "iat": now,
            "exp": now + timedelta(minutes=self._access_token_minutes),
        }
        return jwt.encode(payload, self._secret, algorithm="HS256")

    def decode_access_token(self, token: str) -> AccessTokenClaims:
        try:
            payload = jwt.decode(
                token,
                self._secret,
                algorithms=["HS256"],
                issuer=self._issuer,
            )
            return AccessTokenClaims(
                user_id=UUID(payload["sub"]),
                device_id=UUID(payload["deviceId"]),
            )
        except (KeyError, TypeError, ValueError, jwt.PyJWTError) as error:
            raise InvalidAccessTokenError from error

    def create_refresh_token(self) -> tuple[str, str, datetime]:
        raw_token = token_urlsafe(48)
        return (
            raw_token,
            self.hash_refresh_token(raw_token),
            datetime.now(UTC) + timedelta(days=self._refresh_token_days),
        )

    @staticmethod
    def hash_refresh_token(token: str) -> str:
        return sha256(token.encode("utf-8")).hexdigest()
