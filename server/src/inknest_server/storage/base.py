from datetime import timedelta
from typing import Protocol


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
