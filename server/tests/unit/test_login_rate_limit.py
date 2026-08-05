import pytest

from inknest_server.auth.rate_limit import (
    LoginRateLimiter,
    LoginRateLimitExceededError,
)


class FakeClock:
    def __init__(self) -> None:
        self.now = 100.0

    def __call__(self) -> float:
        return self.now


async def test_client_limit_applies_across_different_accounts() -> None:
    limiter = LoginRateLimiter(
        account_attempts=10,
        client_attempts=2,
        window_seconds=60,
    )

    await limiter.acquire(email="one@example.com", client_id="127.0.0.1")
    await limiter.acquire(email="two@example.com", client_id="127.0.0.1")

    with pytest.raises(LoginRateLimitExceededError) as error:
        await limiter.acquire(email="three@example.com", client_id="127.0.0.1")

    assert error.value.retry_after_seconds == 60


async def test_rate_limit_expires_after_the_window() -> None:
    clock = FakeClock()
    limiter = LoginRateLimiter(
        account_attempts=1,
        client_attempts=10,
        window_seconds=60,
        clock=clock,
    )
    await limiter.acquire(email="writer@example.com", client_id="127.0.0.1")

    with pytest.raises(LoginRateLimitExceededError):
        await limiter.acquire(email="writer@example.com", client_id="127.0.0.1")

    clock.now += 60
    attempt = await limiter.acquire(
        email="writer@example.com",
        client_id="127.0.0.1",
    )

    assert attempt.account_key.startswith("account-client:")


async def test_cancel_removes_reserved_attempt() -> None:
    limiter = LoginRateLimiter(
        account_attempts=1,
        client_attempts=1,
        window_seconds=60,
    )
    attempt = await limiter.acquire(
        email="writer@example.com",
        client_id="127.0.0.1",
    )

    await limiter.cancel(attempt)

    replacement = await limiter.acquire(
        email="writer@example.com",
        client_id="127.0.0.1",
    )
    assert replacement.id != attempt.id
