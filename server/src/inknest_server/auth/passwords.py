from anyio import to_thread
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError


class PasswordManager:
    def __init__(self) -> None:
        self._hasher = PasswordHasher()
        self._dummy_hash = self._hasher.hash("inknest-dummy-password")

    async def hash(self, password: str) -> str:
        return await to_thread.run_sync(self._hasher.hash, password)

    async def verify(self, password_hash: str | None, password: str) -> bool:
        candidate_hash = password_hash or self._dummy_hash
        try:
            valid = await to_thread.run_sync(
                self._hasher.verify,
                candidate_hash,
                password,
            )
        except (InvalidHashError, VerificationError):
            return False
        return bool(valid) and password_hash is not None
