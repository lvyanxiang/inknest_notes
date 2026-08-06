from dataclasses import dataclass
from datetime import timedelta
from typing import Protocol


@dataclass(frozen=True, slots=True)
class StoredObjectMetadata:
    byte_size: int
    content_type: str
    etag: str


class StoredObjectNotFoundError(Exception):
    pass


class StoredObjectChangedError(Exception):
    pass


class ObjectStorage(Protocol):
    async def ping(self) -> None: ...

    async def create_upload_url(
        self,
        object_key: str,
        *,
        expires: timedelta,
    ) -> str: ...

    async def create_download_url(
        self,
        object_key: str,
        *,
        expires: timedelta,
    ) -> str: ...

    async def delete_object(self, object_key: str) -> None: ...

    async def stat_object(self, object_key: str) -> StoredObjectMetadata: ...

    async def copy_object(
        self,
        source_key: str,
        destination_key: str,
        *,
        source_etag: str,
    ) -> None: ...

    async def calculate_sha256(self, object_key: str) -> str: ...
