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
        "folder",
        "notebook",
        "page",
        "infinite_canvas",
        "asset",
        "conflict",
        "tombstone",
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


class SyncBootstrapCounts(SyncApiModel):
    folders: int
    notebooks: int
    pages: int
    infinite_canvases: int
    assets: int


class SyncBootstrapFolder(SyncApiModel):
    id: str
    name: str
    revision: int
    content_hash: str
    created_at: datetime
    updated_at: datetime


class SyncBootstrapNotebook(SyncApiModel):
    id: str
    folder_id: str | None
    title: str
    layout_mode: Literal["paged", "infiniteCanvas"]
    is_archived: bool
    revision: int
    content_hash: str
    content: dict[str, object]
    conflict_of: str | None
    created_at: datetime
    updated_at: datetime


class SyncBootstrapPage(SyncApiModel):
    id: str
    notebook_id: str
    position: int
    width: float
    height: float
    coordinate_space_version: object
    rotation_quarter_turns: int
    template: str
    revision: int
    content_hash: str
    content: dict[str, object]
    conflict_of: str | None
    created_at: datetime
    updated_at: datetime


class SyncBootstrapInfiniteCanvas(SyncApiModel):
    id: str
    notebook_id: str
    background: str
    revision: int
    content_hash: str
    content: dict[str, object]
    created_at: datetime
    updated_at: datetime


class SyncBootstrapAsset(SyncApiModel):
    id: str
    notebook_id: str
    kind: Literal["pdf", "image", "audio"]
    original_filename: str
    relative_path: str
    content_type: str
    byte_size: int
    sha256: str
    created_at: datetime
    updated_at: datetime


class SyncBootstrapResponse(SyncApiModel):
    has_cloud_library: bool
    folder_ids: list[str]
    notebook_ids: list[str]
    folders: list[SyncBootstrapFolder]
    notebooks: list[SyncBootstrapNotebook]
    pages: list[SyncBootstrapPage]
    infinite_canvases: list[SyncBootstrapInfiniteCanvas]
    assets: list[SyncBootstrapAsset]
    counts: SyncBootstrapCounts
    base_cursor: str


class SyncMergeFolderMetadata(SyncApiModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        extra="forbid",
        populate_by_name=True,
    )

    name: str = Field(min_length=1, max_length=200)


class SyncMergeNotebookMetadata(SyncApiModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        extra="forbid",
        populate_by_name=True,
    )

    folder_id: str | None = Field(default=None, max_length=128)
    title: str = Field(min_length=1, max_length=300)
    layout_mode: Literal["paged", "infiniteCanvas"]
    is_archived: bool = False
    content: dict[str, object] = Field(default_factory=dict)


class SyncMergePageMetadata(SyncApiModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        extra="forbid",
        populate_by_name=True,
    )

    notebook_id: str = Field(min_length=1, max_length=128)
    position: int = Field(ge=0)
    width: float = Field(gt=0)
    height: float = Field(gt=0)
    coordinate_space_version: object
    rotation_quarter_turns: int = Field(default=0, ge=0, le=3)
    template: str = Field(default="blank", min_length=1, max_length=32)
    content: dict[str, object]


class SyncMergeInfiniteCanvasMetadata(SyncApiModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        extra="forbid",
        populate_by_name=True,
    )

    notebook_id: str = Field(min_length=1, max_length=128)
    background: str = Field(default="blank", min_length=1, max_length=32)
    content: dict[str, object]


class SyncMergeCreateOperation(SyncApiModel):
    operation_id: str = Field(min_length=1, max_length=128)
    resource_type: Literal["folder", "notebook", "page", "infinite_canvas"]
    resource_id: str = Field(min_length=1, max_length=128)
    metadata: (
        SyncMergeFolderMetadata
        | SyncMergeNotebookMetadata
        | SyncMergePageMetadata
        | SyncMergeInfiniteCanvasMetadata
    )

    @model_validator(mode="after")
    def validate_metadata_type(self) -> SyncMergeCreateOperation:
        expected_type = {
            "folder": SyncMergeFolderMetadata,
            "notebook": SyncMergeNotebookMetadata,
            "page": SyncMergePageMetadata,
            "infinite_canvas": SyncMergeInfiniteCanvasMetadata,
        }[self.resource_type]
        if not isinstance(self.metadata, expected_type):
            raise ValueError("metadata does not match resourceType")
        return self


class SyncMergeCommitRequest(SyncApiModel):
    device_id: UUID
    idempotency_key: str = Field(min_length=1, max_length=128)
    base_cursor: str = Field(min_length=1, max_length=2048)
    operations: list[SyncMergeCreateOperation] = Field(min_length=1, max_length=100)

    @model_validator(mode="after")
    def validate_unique_operations(self) -> SyncMergeCommitRequest:
        operation_ids = [item.operation_id for item in self.operations]
        resources = [(item.resource_type, item.resource_id) for item in self.operations]
        if len(operation_ids) != len(set(operation_ids)):
            raise ValueError("operationId values must be unique within a batch")
        if len(resources) != len(set(resources)):
            raise ValueError("each resource may appear only once within a batch")
        return self


class SyncMergeCreateOperationResult(SyncApiModel):
    operation_id: str
    resource_type: Literal["folder", "notebook", "page", "infinite_canvas"]
    resource_id: str
    outcome: Literal["applied", "unchanged"]
    revision: int | None = None
    content_hash: str | None = None


class SyncMergeCommitResponse(SyncApiModel):
    idempotency_key: str
    replayed: bool
    results: list[SyncMergeCreateOperationResult]
    next_cursor: str


class SyncNotebookMetadata(SyncApiModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        extra="forbid",
        populate_by_name=True,
    )

    title: str = Field(min_length=1, max_length=300)
    is_archived: bool
    folder_id: str | None = Field(default=None, min_length=1, max_length=128)
    page_order: list[str] | None = Field(default=None, min_length=1, max_length=10000)

    @model_validator(mode="after")
    def validate_page_order(self) -> SyncNotebookMetadata:
        if self.page_order is None:
            return self
        if any(not page_id or len(page_id) > 128 for page_id in self.page_order):
            raise ValueError("pageOrder entries must be valid resource IDs")
        if len(self.page_order) != len(set(self.page_order)):
            raise ValueError("pageOrder entries must be unique")
        return self


class SyncFolderMetadata(SyncApiModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        extra="forbid",
        populate_by_name=True,
    )

    name: str = Field(min_length=1, max_length=200)


class SyncCommitOperation(SyncApiModel):
    operation_id: str = Field(min_length=1, max_length=128)
    operation: Literal["upsert", "delete"]
    resource_type: Literal["folder", "notebook", "page", "infinite_canvas"]
    resource_id: str = Field(min_length=1, max_length=128)
    base_revision: int = Field(ge=0)
    content: dict[str, object] | None = None
    metadata: SyncFolderMetadata | SyncNotebookMetadata | None = None
    base_metadata: SyncFolderMetadata | SyncNotebookMetadata | None = None

    @model_validator(mode="after")
    def validate_operation_content(self) -> SyncCommitOperation:
        if (
            self.operation == "upsert"
            and self.content is None
            and self.metadata is None
        ):
            raise ValueError("content or metadata is required for an upsert operation")
        if self.operation == "delete" and (
            self.content is not None
            or self.metadata is not None
            or self.base_metadata is not None
        ):
            raise ValueError(
                "content and metadata must be omitted for a delete operation"
            )
        if self.resource_type == "folder":
            if self.operation == "delete":
                return self
            if self.content is not None:
                raise ValueError("folder upsert does not support content")
            if not isinstance(self.metadata, SyncFolderMetadata):
                raise ValueError("folder upsert requires folder metadata")
            if self.base_metadata is not None and not isinstance(
                self.base_metadata, SyncFolderMetadata
            ):
                raise ValueError("folder baseMetadata must match folder metadata")
        elif self.metadata is not None:
            if (
                self.resource_type != "notebook"
                or not isinstance(self.metadata, SyncNotebookMetadata)
                or not isinstance(self.base_metadata, SyncNotebookMetadata)
            ):
                raise ValueError("notebook metadata requires notebook baseMetadata")
            if (self.metadata.page_order is None) != (
                self.base_metadata.page_order is None
            ):
                raise ValueError(
                    "notebook pageOrder requires a matching baseMetadata pageOrder"
                )
        elif self.base_metadata is not None:
            raise ValueError("baseMetadata requires metadata")
        return self


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
    resource_type: Literal["folder", "notebook", "page", "infinite_canvas"]
    resource_id: str
    revision: int
    content_hash: str
    changed: bool
    outcome: Literal["applied", "unchanged", "conflict", "deleted", "delete_conflict"]
    conflict: SyncConflictResponse | None = None
    tombstone: SyncTombstoneResponse | None = None


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


class SyncTombstoneResponse(SyncApiModel):
    id: UUID
    resource_type: Literal["notebook", "page", "infinite_canvas"]
    resource_id: str
    base_revision: int
    resource_revision: int
    deleted_revision: int | None
    content_hash: str
    content: dict[str, object]
    structure_metadata: dict[str, object]
    deleted_by_device_id: UUID | None
    deleted_at: datetime
    state: Literal["active", "restored"]
    conflict_kind: Literal["delete_after_edit", "edit_after_delete"] | None
    resolution: Literal["restored_snapshot", "preserved_edit"] | None
    conflicting_device_id: UUID | None
    restored_by_device_id: UUID | None
    restored_at: datetime | None
    created_at: datetime


class ResolveSyncConflictRequest(SyncApiModel):
    resolution: Literal["keep_original", "use_conflict", "keep_both"]
