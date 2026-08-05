import asyncio
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass
from hashlib import sha256
from math import ceil
from time import monotonic
from uuid import UUID, uuid4

from inknest_server.config import Settings


@dataclass(frozen=True)
class LoginAttempt:
    id: UUID
    account_key: str
    client_key: str


class LoginRateLimitExceededError(Exception):
    def __init__(self, retry_after_seconds: int) -> None:
        super().__init__("login rate limit exceeded")
        self.retry_after_seconds = retry_after_seconds


class LoginRateLimiter:
    def __init__(
        self,
        *,
        account_attempts: int,
        client_attempts: int,
        window_seconds: int,
        clock: Callable[[], float] = monotonic,
    ) -> None:
        self._account_attempts = account_attempts
        self._client_attempts = client_attempts
        self._window_seconds = window_seconds
        self._clock = clock
        self._attempts: dict[str, deque[tuple[UUID, float]]] = {}
        self._lock = asyncio.Lock()

    @classmethod
    def from_settings(cls, settings: Settings) -> "LoginRateLimiter":
        return cls(
            account_attempts=settings.login_rate_limit_account_attempts,
            client_attempts=settings.login_rate_limit_ip_attempts,
            window_seconds=settings.login_rate_limit_window_seconds,
        )

    async def acquire(self, *, email: str, client_id: str) -> LoginAttempt:
        account_key = self._key("account-client", f"{email}\0{client_id}")
        client_key = self._key("client", client_id)

        async with self._lock:
            now = self._clock()
            self._prune_all(now)
            retry_after = max(
                self._retry_after(
                    account_key,
                    limit=self._account_attempts,
                    now=now,
                ),
                self._retry_after(
                    client_key,
                    limit=self._client_attempts,
                    now=now,
                ),
            )
            if retry_after > 0:
                raise LoginRateLimitExceededError(retry_after)

            attempt = LoginAttempt(
                id=uuid4(),
                account_key=account_key,
                client_key=client_key,
            )
            self._attempts.setdefault(account_key, deque()).append((attempt.id, now))
            self._attempts.setdefault(client_key, deque()).append((attempt.id, now))
            return attempt

    async def mark_succeeded(self, attempt: LoginAttempt) -> None:
        async with self._lock:
            self._attempts.pop(attempt.account_key, None)
            self._remove_attempt(attempt.client_key, attempt.id)

    async def cancel(self, attempt: LoginAttempt) -> None:
        async with self._lock:
            self._remove_attempt(attempt.account_key, attempt.id)
            self._remove_attempt(attempt.client_key, attempt.id)

    def _retry_after(self, key: str, *, limit: int, now: float) -> int:
        attempts = self._attempts.get(key)
        if attempts is None or len(attempts) < limit:
            return 0
        oldest_time = attempts[0][1]
        return max(1, ceil(oldest_time + self._window_seconds - now))

    def _prune_all(self, now: float) -> None:
        cutoff = now - self._window_seconds
        for key in tuple(self._attempts):
            attempts = self._attempts[key]
            while attempts and attempts[0][1] <= cutoff:
                attempts.popleft()
            if not attempts:
                del self._attempts[key]

    def _remove_attempt(self, key: str, attempt_id: UUID) -> None:
        attempts = self._attempts.get(key)
        if attempts is None:
            return
        remaining = deque(item for item in attempts if item[0] != attempt_id)
        if remaining:
            self._attempts[key] = remaining
        else:
            self._attempts.pop(key, None)

    @staticmethod
    def _key(namespace: str, value: str) -> str:
        digest = sha256(value.encode("utf-8")).hexdigest()
        return f"{namespace}:{digest}"
