import hashlib
from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import timedelta

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import SecretStr
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server import models  # noqa: F401
from inknest_server.config import Settings
from inknest_server.db import Database
from inknest_server.db.base import Base
from inknest_server.main import create_app
from inknest_server.services.readiness import ReadinessChecks
from inknest_server.storage import (
    StoredObjectChangedError,
    StoredObjectMetadata,
    StoredObjectNotFoundError,
)


@dataclass(frozen=True, slots=True)
class FakeStoredObject:
    content: bytes
    content_type: str
    etag: str


class FakeObjectStorage:
    def __init__(self) -> None:
        self.upload_requests: list[tuple[str, timedelta]] = []
        self.deleted_objects: list[str] = []
        self.objects: dict[str, FakeStoredObject] = {}

    def put_object(self, object_key: str, content: bytes, *, content_type: str) -> None:
        self.objects[object_key] = FakeStoredObject(
            content=content,
            content_type=content_type,
            etag=hashlib.md5(content, usedforsecurity=False).hexdigest(),
        )

    async def ping(self) -> None:
        return None

    async def create_upload_url(self, object_key: str, *, expires: timedelta) -> str:
        self.upload_requests.append((object_key, expires))
        return f"http://object-storage.test/upload/{object_key}"

    async def create_download_url(self, object_key: str, *, expires: timedelta) -> str:
        return f"http://object-storage.test/download/{object_key}"

    async def delete_object(self, object_key: str) -> None:
        self.deleted_objects.append(object_key)
        self.objects.pop(object_key, None)

    async def stat_object(self, object_key: str) -> StoredObjectMetadata:
        stored = self.objects.get(object_key)
        if stored is None:
            raise StoredObjectNotFoundError(object_key)
        return StoredObjectMetadata(
            byte_size=len(stored.content),
            content_type=stored.content_type,
            etag=stored.etag,
        )

    async def copy_object(
        self,
        source_key: str,
        destination_key: str,
        *,
        source_etag: str,
    ) -> None:
        stored = self.objects.get(source_key)
        if stored is None:
            raise StoredObjectNotFoundError(source_key)
        if stored.etag != source_etag:
            raise StoredObjectChangedError(source_key)
        self.objects[destination_key] = stored

    async def calculate_sha256(self, object_key: str) -> str:
        stored = self.objects.get(object_key)
        if stored is None:
            raise StoredObjectNotFoundError(object_key)
        return hashlib.sha256(stored.content).hexdigest()


class HealthyReadinessChecker:
    async def check(self) -> ReadinessChecks:
        return {
            "database": {"status": "ok"},
            "objectStorage": {"status": "ok"},
        }


@pytest.fixture
def test_settings() -> Settings:
    return Settings(
        environment="test",
        database_url="sqlite+aiosqlite:///:memory:",
        jwt_secret=SecretStr("test-only-jwt-secret-that-is-at-least-32-characters"),
        login_rate_limit_account_attempts=2,
        login_rate_limit_ip_attempts=100,
        login_rate_limit_window_seconds=60,
    )


@pytest.fixture
async def database(test_settings: Settings) -> AsyncIterator[Database]:
    database = Database(test_settings.database_url)
    async with database.engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    yield database
    await database.close()


@pytest.fixture
async def db_session(database: Database) -> AsyncIterator[AsyncSession]:
    async with database.session() as session:
        yield session


@pytest.fixture
def object_storage() -> FakeObjectStorage:
    return FakeObjectStorage()


@pytest.fixture
async def client(
    test_settings: Settings,
    database: Database,
    object_storage: FakeObjectStorage,
) -> AsyncIterator[AsyncClient]:
    app = create_app(
        settings=test_settings,
        readiness_checker=HealthyReadinessChecker(),
        database=database,
        object_storage=object_storage,
    )
    transport = ASGITransport(app=app)
    async with app.router.lifespan_context(app):
        async with AsyncClient(
            transport=transport,
            base_url="http://testserver",
        ) as test_client:
            yield test_client
