from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator
from pydantic.alias_generators import to_camel


class AssetApiModel(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        from_attributes=True,
        populate_by_name=True,
    )


class CreateAssetUploadRequest(AssetApiModel):
    notebook_id: str = Field(min_length=1, max_length=128)
    asset_id: str = Field(min_length=1, max_length=128)
    kind: Literal["pdf", "image", "audio"]
    filename: str = Field(min_length=1, max_length=255)
    content_type: str = Field(min_length=1, max_length=255)
    byte_size: int = Field(gt=0)
    sha256: str = Field(pattern=r"^[0-9a-fA-F]{64}$")

    @field_validator("notebook_id", "asset_id", "filename", "content_type")
    @classmethod
    def strip_non_empty_strings(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("must not be empty")
        return stripped

    @field_validator("content_type")
    @classmethod
    def normalize_content_type(cls, value: str) -> str:
        return value.lower()

    @field_validator("sha256")
    @classmethod
    def normalize_sha256(cls, value: str) -> str:
        return value.lower()


class AssetUploadSessionResponse(AssetApiModel):
    upload_id: UUID
    asset_id: str
    status: str
    object_key: str
    upload_url: str
    method: Literal["PUT"] = "PUT"
    required_headers: dict[str, str]
    upload_url_expires_at: datetime
    session_expires_at: datetime


class AssetResponse(AssetApiModel):
    asset_id: str
    notebook_id: str
    kind: str
    filename: str
    content_type: str
    byte_size: int
    sha256: str
    status: Literal["ready"] = "ready"
    created_at: datetime


class AssetDownloadUrlResponse(AssetApiModel):
    asset_id: str
    filename: str
    content_type: str
    byte_size: int
    sha256: str
    download_url: str
    method: Literal["GET"] = "GET"
    expires_at: datetime
