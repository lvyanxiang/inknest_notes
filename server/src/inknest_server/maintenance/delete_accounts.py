import asyncio
import json

from inknest_server.auth import LoginRateLimiter, PasswordManager, TokenManager
from inknest_server.auth.service import AuthService
from inknest_server.config import Settings
from inknest_server.db import Database
from inknest_server.storage import MinioStorage


async def _run() -> None:
    settings = Settings()
    database = Database(settings.database_url)
    storage = MinioStorage(
        endpoint=settings.minio_endpoint,
        public_endpoint=settings.minio_public_endpoint,
        access_key=settings.minio_access_key.get_secret_value(),
        secret_key=settings.minio_secret_key.get_secret_value(),
        secure=settings.minio_secure,
        public_secure=settings.minio_public_secure,
        region=settings.minio_region,
        bucket=settings.minio_bucket,
    )
    try:
        async with database.session() as session:
            service = AuthService(
                session,
                PasswordManager(),
                TokenManager(settings),
                LoginRateLimiter.from_settings(settings),
                storage,
            )
            completed, pending = await service.retry_pending_account_deletions()
            print(json.dumps({"completed": completed, "pending": pending}))
            if pending:
                raise SystemExit(1)
    finally:
        await database.close()


def main() -> None:
    asyncio.run(_run())


if __name__ == "__main__":
    main()
