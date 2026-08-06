from functools import lru_cache
from typing import Literal

from pydantic import Field, SecretStr, model_validator
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
    minio_public_endpoint: str | None = None
    minio_access_key: SecretStr = SecretStr("inknest-minio")
    minio_secret_key: SecretStr = SecretStr("inknest-minio-dev")
    minio_secure: bool = False
    minio_public_secure: bool | None = None
    minio_region: str = "us-east-1"
    minio_bucket: str = "inknest-private"
    asset_upload_url_minutes: int = Field(default=15, ge=1, le=60)
    asset_upload_session_hours: int = Field(default=24, ge=1, le=168)
    asset_download_url_minutes: int = Field(default=15, ge=1, le=60)
    max_asset_upload_bytes: int = Field(default=536_870_912, ge=1)

    jwt_secret: SecretStr = SecretStr(
        "development-only-replace-this-jwt-secret-before-production"
    )
    jwt_issuer: str = "inknest-server"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    login_rate_limit_account_attempts: int = Field(default=5, ge=1)
    login_rate_limit_ip_attempts: int = Field(default=25, ge=1)
    login_rate_limit_window_seconds: int = Field(default=300, ge=1)

    @model_validator(mode="after")
    def reject_development_secret_in_production(self) -> "Settings":
        secret = self.jwt_secret.get_secret_value()
        if len(secret) < 32:
            raise ValueError("INKNEST_JWT_SECRET must contain at least 32 characters")
        if self.environment == "production" and secret.startswith("development-only"):
            raise ValueError("set a unique INKNEST_JWT_SECRET in production")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
