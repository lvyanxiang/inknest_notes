from datetime import timedelta

from anyio import to_thread
from minio import Minio


class MinioStorage:
    def __init__(
        self,
        *,
        endpoint: str,
        access_key: str,
        secret_key: str,
        secure: bool,
        bucket: str,
    ) -> None:
        self._bucket = bucket
        self._client = Minio(
            endpoint,
            access_key=access_key,
            secret_key=secret_key,
            secure=secure,
        )

    async def ping(self) -> None:
        exists = await to_thread.run_sync(
            lambda: self._client.bucket_exists(self._bucket)
        )
        if not exists:
            raise RuntimeError("The configured MinIO bucket does not exist.")

    async def create_upload_url(
        self,
        object_key: str,
        *,
        expires: timedelta,
    ) -> str:
        return await to_thread.run_sync(
            lambda: self._client.presigned_put_object(
                self._bucket,
                object_key,
                expires=expires,
            )
        )

    async def create_download_url(
        self,
        object_key: str,
        *,
        expires: timedelta,
    ) -> str:
        return await to_thread.run_sync(
            lambda: self._client.presigned_get_object(
                self._bucket,
                object_key,
                expires=expires,
            )
        )
