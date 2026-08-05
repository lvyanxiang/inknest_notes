from functools import lru_cache
from typing import Literal

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="INKNEST_",
        extra="ignore",
    )

    app_name: str = "InkNest Server"
    api_prefix: str = "/api/v1"
    environment: Literal["development", "test", "production"] = "development"
    log_level: str = "INFO"

    database_url: str = (
        "postgresql+psycopg://inknest:inknest-postgres-dev@localhost:5432/inknest"
    )

    minio_endpoint: str = "localhost:9000"
    minio_access_key: SecretStr = SecretStr("inknest-minio")
    minio_secret_key: SecretStr = SecretStr("inknest-minio-dev")
    minio_secure: bool = False
    minio_bucket: str = "inknest-private"


@lru_cache
def get_settings() -> Settings:
    return Settings()
