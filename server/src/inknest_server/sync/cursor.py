import base64
import binascii
import hashlib
import hmac
import json
from uuid import UUID

from inknest_server.config import Settings


class InvalidSyncCursorError(Exception):
    pass


class SyncCursorCodec:
    def __init__(self, settings: Settings) -> None:
        secret = settings.jwt_secret.get_secret_value().encode("utf-8")
        self._key = hashlib.sha256(b"inknest-sync-cursor-v1\0" + secret).digest()

    def encode(self, *, user_id: UUID, sequence: int) -> str:
        if sequence < 0:
            raise ValueError("sequence must be non-negative")
        payload = json.dumps(
            {"sequence": sequence, "userId": str(user_id), "version": 1},
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
        signature = hmac.new(self._key, payload, hashlib.sha256).digest()
        return f"{self._encode(payload)}.{self._encode(signature)}"

    def decode(self, cursor: str, *, user_id: UUID) -> int:
        try:
            encoded_payload, encoded_signature = cursor.split(".", maxsplit=1)
            payload = self._decode(encoded_payload)
            signature = self._decode(encoded_signature)
            expected_signature = hmac.new(self._key, payload, hashlib.sha256).digest()
            if not hmac.compare_digest(signature, expected_signature):
                raise InvalidSyncCursorError
            decoded = json.loads(payload)
            sequence = decoded["sequence"]
            if (
                decoded["version"] != 1
                or UUID(decoded["userId"]) != user_id
                or isinstance(sequence, bool)
                or not isinstance(sequence, int)
                or sequence < 0
            ):
                raise InvalidSyncCursorError
            return sequence
        except (
            InvalidSyncCursorError,
            UnicodeDecodeError,
            ValueError,
            KeyError,
            TypeError,
            AttributeError,
            binascii.Error,
            json.JSONDecodeError,
        ) as error:
            raise InvalidSyncCursorError from error

    @staticmethod
    def _encode(value: bytes) -> str:
        return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")

    @staticmethod
    def _decode(value: str) -> bytes:
        padding = "=" * (-len(value) % 4)
        return base64.b64decode(value + padding, altchars=b"-_", validate=True)
