import hashlib
from datetime import timedelta

from anyio import to_thread
from minio import Minio
from minio.commonconfig import CopySource
from minio.error import S3Error

from inknest_server.storage.base import (
    StoredObjectChangedError,
    StoredObjectMetadata,
    StoredObjectNotFoundError,
)


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

    async def stat_object(self, object_key: str) -> StoredObjectMetadata:
        def stat() -> StoredObjectMetadata:
            try:
                result = self._client.stat_object(self._bucket, object_key)
            except S3Error as error:
                if error.code in {"NoSuchKey", "NoSuchObject"}:
                    raise StoredObjectNotFoundError(object_key) from error
                raise
            if result.size is None or result.etag is None:
                raise RuntimeError("MinIO returned incomplete object metadata.")
            return StoredObjectMetadata(
                byte_size=result.size,
                content_type=result.content_type or "application/octet-stream",
                etag=result.etag,
            )

        return await to_thread.run_sync(stat)

    async def copy_object(
        self,
        source_key: str,
        destination_key: str,
        *,
        source_etag: str,
    ) -> None:
        def copy() -> None:
            try:
                self._client.copy_object(
                    self._bucket,
                    destination_key,
                    CopySource(
                        self._bucket,
                        source_key,
                        match_etag=source_etag,
                    ),
                )
            except S3Error as error:
                if error.code in {"NoSuchKey", "NoSuchObject"}:
                    raise StoredObjectNotFoundError(source_key) from error
                if error.code == "PreconditionFailed":
                    raise StoredObjectChangedError(source_key) from error
                raise

        await to_thread.run_sync(copy)

    async def calculate_sha256(self, object_key: str) -> str:
        def calculate() -> str:
            try:
                response = self._client.get_object(self._bucket, object_key)
            except S3Error as error:
                if error.code in {"NoSuchKey", "NoSuchObject"}:
                    raise StoredObjectNotFoundError(object_key) from error
                raise

            digest = hashlib.sha256()
            try:
                for chunk in response.stream(amt=1024 * 1024):
                    digest.update(chunk)
            finally:
                response.close()
                response.release_conn()
            return digest.hexdigest()

        return await to_thread.run_sync(calculate)
