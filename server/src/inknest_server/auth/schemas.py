from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
from pydantic.alias_generators import to_camel


class ApiModel(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        from_attributes=True,
        populate_by_name=True,
    )


class RegisterRequest(ApiModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    device_name: str = Field(min_length=1, max_length=120)
    platform: str = Field(min_length=1, max_length=40)

    @field_validator("device_name", "platform")
    @classmethod
    def strip_non_empty_device_fields(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("must not be empty")
        return stripped


class LoginRequest(RegisterRequest):
    pass


class RefreshRequest(ApiModel):
    refresh_token: str = Field(min_length=32, max_length=512)


class LogoutRequest(RefreshRequest):
    pass


class UserResponse(ApiModel):
    id: UUID
    email: EmailStr
    created_at: datetime


class DeviceResponse(ApiModel):
    id: UUID
    name: str
    platform: str
    created_at: datetime
    last_seen_at: datetime
    revoked_at: datetime | None
    current: bool = False


class TokenResponse(ApiModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserResponse
    device: DeviceResponse
