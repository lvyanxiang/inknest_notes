from datetime import timedelta

from anyio import to_thread
from minio import Minio


class MinioStorage:
    def __init__(
        self,
        *,
        endpoint: str,
        public_endpoint: str | None = None,
        access_key: str,
        secret_key: str,
        secure: bool,
        public_secure: bool | None = None,
        region: str = "us-east-1",
        bucket: str,
    ) -> None:
        self._bucket = bucket
        self._client = Minio(
            endpoint,
            access_key=access_key,
            secret_key=secret_key,
            secure=secure,
            region=region,
        )
        self._signing_client = Minio(
            public_endpoint or endpoint,
            access_key=access_key,
            secret_key=secret_key,
            secure=secure if public_secure is None else public_secure,
            region=region,
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
            lambda: self._signing_client.presigned_put_object(
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
            lambda: self._signing_client.presigned_get_object(
                self._bucket,
                object_key,
                expires=expires,
            )
        )

    async def delete_object(self, object_key: str) -> None:
        await to_thread.run_sync(
            lambda: self._client.remove_object(self._bucket, object_key)
        )
