"""Delete one InkNest cloud account.

Set ACCOUNT_EMAIL below, stop the API, then run from server/:
    uv run python scripts/purge_account.py
"""

import asyncio

from sqlalchemy import delete, select

from inknest_server.config import Settings
from inknest_server.db import Database
from inknest_server.models import AccountDeletionRequest, User
from inknest_server.storage import MinioStorage

# 修改为需要清空的账号邮箱。
ACCOUNT_EMAIL = "user@example.com"


async def main() -> None:
    email = ACCOUNT_EMAIL.strip().lower()
    if email == "user@example.com":
        raise SystemExit("请先修改脚本顶部的 ACCOUNT_EMAIL")

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
            user = await session.scalar(select(User).where(User.email == email))
            if user is None:
                raise SystemExit(f"账号不存在：{email}")

            object_prefix = f"users/{user.id}/"
            object_keys = await storage.list_object_keys(object_prefix)
            print(f"账号：{user.email}")
            print(f"用户 ID：{user.id}")
            print(f"MinIO 文件数：{len(object_keys)}")

            confirmation = input("输入账号邮箱确认永久删除：").strip().lower()
            if confirmation != email:
                raise SystemExit("输入不匹配，已取消")

            for object_key in object_keys:
                await storage.delete_object(object_key)

            remaining_keys = await storage.list_object_keys(object_prefix)
            if remaining_keys:
                raise RuntimeError(
                    f"仍有 {len(remaining_keys)} 个 MinIO 文件，数据库未删除"
                )

            await session.execute(
                delete(AccountDeletionRequest).where(
                    AccountDeletionRequest.user_id == user.id
                )
            )
            await session.delete(user)
            await session.commit()
            print("账号、关联数据库信息以及 PDF/图片/音频文件已删除")
    finally:
        await database.close()


if __name__ == "__main__":
    asyncio.run(main())
