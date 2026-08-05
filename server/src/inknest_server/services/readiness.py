import asyncio
from collections.abc import Awaitable, Callable
from typing import Protocol

from inknest_server.db import Database
from inknest_server.errors import DependenciesUnavailableError
from inknest_server.storage import ObjectStorage

ReadinessChecks = dict[str, dict[str, str]]


class ReadinessChecker(Protocol):
    async def check(self) -> ReadinessChecks: ...


class ReadinessService:
    def __init__(self, database: Database, storage: ObjectStorage) -> None:
        self._database = database
        self._storage = storage

    async def check(self) -> ReadinessChecks:
        check_functions: dict[str, Callable[[], Awaitable[None]]] = {
            "database": self._database.ping,
            "objectStorage": self._storage.ping,
        }
        results = await asyncio.gather(
            *(check() for check in check_functions.values()),
            return_exceptions=True,
        )

        checks: ReadinessChecks = {}
        for name, result in zip(check_functions, results, strict=True):
            checks[name] = (
                {"status": "error", "reason": type(result).__name__}
                if isinstance(result, BaseException)
                else {"status": "ok"}
            )

        if any(check["status"] != "ok" for check in checks.values()):
            raise DependenciesUnavailableError(checks)
        return checks
