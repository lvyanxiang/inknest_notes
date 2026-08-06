from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel


class SyncApiModel(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        from_attributes=True,
        populate_by_name=True,
    )


class SyncChangeResponse(SyncApiModel):
    change_id: UUID
    resource_type: Literal[
        "folder", "notebook", "page", "infinite_canvas", "asset", "conflict"
    ]
    resource_id: str
    operation: Literal["upsert", "delete"]
    revision: int | None
    content_hash: str | None
    payload: dict[str, object] | None
    device_id: UUID | None
    created_at: datetime


class SyncChangesResponse(SyncApiModel):
    changes: list[SyncChangeResponse]
    next_cursor: str
    has_more: bool


class SyncCommitOperation(SyncApiModel):
    operation_id: str = Field(min_length=1, max_length=128)
    operation: Literal["upsert"]
    resource_type: Literal["notebook", "page", "infinite_canvas"]
    resource_id: str = Field(min_length=1, max_length=128)
    base_revision: int = Field(ge=0)
    content: dict[str, object]


class SyncCommitRequest(SyncApiModel):
    device_id: UUID
    idempotency_key: str = Field(min_length=1, max_length=128)
    base_cursor: str = Field(min_length=1, max_length=2048)
    operations: list[SyncCommitOperation] = Field(min_length=1, max_length=100)

    @model_validator(mode="after")
    def validate_unique_operations(self) -> SyncCommitRequest:
        operation_ids = [item.operation_id for item in self.operations]
        resources = [(item.resource_type, item.resource_id) for item in self.operations]
        if len(operation_ids) != len(set(operation_ids)):
            raise ValueError("operationId values must be unique within a batch")
        if len(resources) != len(set(resources)):
            raise ValueError("each resource may appear only once within a batch")
        return self


class SyncCommitOperationResult(SyncApiModel):
    operation_id: str
    resource_type: Literal["notebook", "page", "infinite_canvas"]
    resource_id: str
    revision: int
    content_hash: str
    changed: bool
    outcome: Literal["applied", "unchanged", "conflict"]
    conflict: SyncConflictResponse | None = None


class SyncCommitResponse(SyncApiModel):
    idempotency_key: str
    replayed: bool
    results: list[SyncCommitOperationResult]
    next_cursor: str


class SyncConflictResponse(SyncApiModel):
    id: UUID
    resource_type: Literal["notebook", "page"]
    original_resource_id: str
    copy_resource_id: str
    copy_display_name: str
    base_revision: int
    current_revision: int
    submitted_content_hash: str
    submitted_content: dict[str, object]
    current_content_hash: str
    current_content: dict[str, object]
    source_device_id: UUID | None
    status: Literal["pending", "resolved"]
    resolution: Literal["keep_original", "use_conflict", "keep_both"] | None
    resolved_by_device_id: UUID | None
    resolved_at: datetime | None
    created_at: datetime


class ResolveSyncConflictRequest(SyncApiModel):
    resolution: Literal["keep_original", "use_conflict", "keep_both"]
