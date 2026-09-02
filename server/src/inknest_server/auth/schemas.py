from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
from pydantic.alias_generators import to_camel


class ApiModel(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        from_attributes=True,
        populate_by_name=True,
    )


class DeviceAuthenticationRequest(ApiModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    device_name: str = Field(min_length=1, max_length=120)
    platform: str = Field(min_length=1, max_length=40)
    client_instance_id: str | None = Field(default=None, min_length=1, max_length=128)

    @field_validator("device_name", "platform", "client_instance_id")
    @classmethod
    def strip_non_empty_device_fields(cls, value: str | None) -> str | None:
        if value is None:
            return None
        stripped = value.strip()
        if not stripped:
            raise ValueError("must not be empty")
        return stripped


class RegisterRequest(DeviceAuthenticationRequest):
    privacy_policy_version: str = Field(min_length=1, max_length=32)
    terms_version: str = Field(min_length=1, max_length=32)


class LoginRequest(DeviceAuthenticationRequest):
    pass


class RefreshRequest(ApiModel):
    refresh_token: str = Field(min_length=32, max_length=512)


class LogoutRequest(RefreshRequest):
    pass


class AcceptAgreementsRequest(ApiModel):
    privacy_policy_version: str = Field(min_length=1, max_length=32)
    terms_version: str = Field(min_length=1, max_length=32)


class ChangePasswordRequest(ApiModel):
    current_password: str = Field(min_length=8, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


class DeleteAccountRequest(ApiModel):
    password: str = Field(min_length=8, max_length=128)
    confirmation: Literal["DELETE"]


class AccountDeletionResponse(ApiModel):
    status: Literal["pending", "completed"]
    cloud_deletion_complete: bool
    local_data_retained: bool = True


class AgreementVersionsResponse(ApiModel):
    privacy_policy_version: str
    terms_version: str
    effective_date: str


class UserResponse(ApiModel):
    id: UUID
    email: EmailStr
    created_at: datetime
    privacy_policy_version: str | None
    terms_version: str | None
    agreements_accepted_at: datetime | None


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
