from datetime import datetime
from pathlib import PurePosixPath
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
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
    relative_path: str = Field(min_length=1, max_length=1024)
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

    @field_validator("relative_path")
    @classmethod
    def validate_relative_path(cls, value: str) -> str:
        normalized = value.strip()
        path = PurePosixPath(normalized)
        if (
            normalized != value
            or "\\" in normalized
            or path.is_absolute()
            or not path.parts
            or path.parts[0] != "assets"
            or len(path.parts) < 2
            or str(path) != normalized
            or any(part in {"", ".", ".."} for part in path.parts)
        ):
            raise ValueError("must be a normalized notebook-relative assets path")
        return normalized

    @model_validator(mode="after")
    def validate_kind_path(self) -> "CreateAssetUploadRequest":
        parts = PurePosixPath(self.relative_path).parts
        required_prefix = {
            "image": ("assets", "images"),
            "audio": ("assets", "audio"),
        }.get(self.kind)
        if required_prefix is not None and parts[:2] != required_prefix:
            raise ValueError(
                f"{self.kind} assets must use {'/'.join(required_prefix)}/"
            )
        return self


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
    relative_path: str
    content_type: str
    byte_size: int
    sha256: str
    status: Literal["ready"] = "ready"
    created_at: datetime


class AssetDownloadUrlResponse(AssetApiModel):
    asset_id: str
    filename: str
    relative_path: str
    content_type: str
    byte_size: int
    sha256: str
    download_url: str
    method: Literal["GET"] = "GET"
    expires_at: datetime
