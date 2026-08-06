import argparse
import asyncio
import json

from inknest_server.assets.cleanup import AssetCleanupService
from inknest_server.config import Settings
from inknest_server.db import Database
from inknest_server.storage import MinioStorage


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Preview or execute safe InkNest asset cleanup."
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Apply state changes and eligible deletions. Default is dry-run.",
    )
    return parser.parse_args()


async def _run(*, execute: bool) -> None:
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
            result = await AssetCleanupService(
                session,
                storage,
                settings,
            ).run(execute=execute)
            print(json.dumps(result.to_dict(), sort_keys=True))
            if result.failures:
                raise SystemExit(1)
    finally:
        await database.close()


def main() -> None:
    args = _parse_args()
    asyncio.run(_run(execute=args.execute))


if __name__ == "__main__":
    main()
