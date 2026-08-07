from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    ForeignKeyConstraint,
    Identity,
    Index,
    Integer,
    String,
    UniqueConstraint,
    false,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from inknest_server.db.base import Base


class Folder(Base):
    __tablename__ = "folders"
    __table_args__ = (
        CheckConstraint("revision >= 0", name="ck_folders_revision"),
        CheckConstraint(
            "(revision = 0 AND content_hash = '') OR "
            "(revision > 0 AND length(content_hash) = 64)",
            name="ck_folders_content_version",
        ),
        Index("ix_folders_user_id_updated_at", "user_id", "updated_at"),
    )

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    name: Mapped[str] = mapped_column(String(200))
    revision: Mapped[int] = mapped_column(BigInteger, default=0, server_default="0")
    content_hash: Mapped[str] = mapped_column(String(64), default="", server_default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Notebook(Base):
    __tablename__ = "notebooks"
    __table_args__ = (
        ForeignKeyConstraint(
            ["folder_id", "user_id"],
            ["folders.id", "folders.user_id"],
            name="fk_notebooks_folder_owner",
        ),
        ForeignKeyConstraint(
            ["conflict_of", "user_id"],
            ["notebooks.id", "notebooks.user_id"],
            name="fk_notebooks_conflict_origin_owner",
        ),
        CheckConstraint(
            "layout_mode IN ('paged', 'infiniteCanvas')",
            name="ck_notebooks_layout_mode",
        ),
        CheckConstraint("revision >= 0", name="ck_notebooks_revision"),
        CheckConstraint(
            "(revision = 0 AND content_hash = '') OR "
            "(revision > 0 AND length(content_hash) = 64)",
            name="ck_notebooks_content_version",
        ),
        Index("ix_notebooks_user_id_updated_at", "user_id", "updated_at"),
        Index("ix_notebooks_user_id_folder_id", "user_id", "folder_id"),
    )

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    folder_id: Mapped[str | None] = mapped_column(String(128))
    title: Mapped[str] = mapped_column(String(300))
    layout_mode: Mapped[str] = mapped_column(
        String(32), default="paged", server_default="paged"
    )
    is_archived: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default=false()
    )
    revision: Mapped[int] = mapped_column(BigInteger, default=0, server_default="0")
    content_hash: Mapped[str] = mapped_column(String(64), default="", server_default="")
    content: Mapped[dict[str, object]] = mapped_column(
        JSON, default=dict, server_default="{}"
    )
    conflict_of: Mapped[str | None] = mapped_column(String(128))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Page(Base):
    __tablename__ = "pages"
    __table_args__ = (
        UniqueConstraint(
            "notebook_id",
            "user_id",
            "position",
            name="uq_pages_notebook_owner_position",
        ),
        ForeignKeyConstraint(
            ["notebook_id", "user_id"],
            ["notebooks.id", "notebooks.user_id"],
            name="fk_pages_notebook_owner",
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["conflict_of", "user_id"],
            ["pages.id", "pages.user_id"],
            name="fk_pages_conflict_origin_owner",
        ),
        CheckConstraint("position >= 0", name="ck_pages_position"),
        CheckConstraint("width > 0", name="ck_pages_width"),
        CheckConstraint("height > 0", name="ck_pages_height"),
        CheckConstraint(
            "rotation_quarter_turns BETWEEN 0 AND 3",
            name="ck_pages_rotation_quarter_turns",
        ),
        CheckConstraint("revision >= 0", name="ck_pages_revision"),
        CheckConstraint(
            "(revision = 0 AND content_hash = '') OR "
            "(revision > 0 AND length(content_hash) = 64)",
            name="ck_pages_content_version",
        ),
        Index("ix_pages_user_id_notebook_id", "user_id", "notebook_id"),
    )

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    notebook_id: Mapped[str] = mapped_column(String(128))
    position: Mapped[int] = mapped_column(Integer)
    width: Mapped[float] = mapped_column(Float)
    height: Mapped[float] = mapped_column(Float)
    coordinate_space_version: Mapped[object] = mapped_column(JSON)
    rotation_quarter_turns: Mapped[int] = mapped_column(
        Integer, default=0, server_default="0"
    )
    template: Mapped[str] = mapped_column(
        String(32), default="blank", server_default="blank"
    )
    revision: Mapped[int] = mapped_column(BigInteger, default=0, server_default="0")
    content_hash: Mapped[str] = mapped_column(String(64), default="", server_default="")
    content: Mapped[dict[str, object]] = mapped_column(
        JSON, default=dict, server_default="{}"
    )
    conflict_of: Mapped[str | None] = mapped_column(String(128))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class InfiniteCanvas(Base):
    __tablename__ = "infinite_canvases"
    __table_args__ = (
        UniqueConstraint(
            "notebook_id", "user_id", name="uq_infinite_canvases_notebook_owner"
        ),
        ForeignKeyConstraint(
            ["notebook_id", "user_id"],
            ["notebooks.id", "notebooks.user_id"],
            name="fk_infinite_canvases_notebook_owner",
            ondelete="CASCADE",
        ),
        CheckConstraint("revision >= 0", name="ck_infinite_canvases_revision"),
        CheckConstraint(
            "(revision = 0 AND content_hash = '') OR "
            "(revision > 0 AND length(content_hash) = 64)",
            name="ck_infinite_canvases_content_version",
        ),
        Index("ix_infinite_canvases_user_id_notebook_id", "user_id", "notebook_id"),
    )

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    notebook_id: Mapped[str] = mapped_column(String(128))
    background: Mapped[str] = mapped_column(
        String(32), default="blank", server_default="blank"
    )
    revision: Mapped[int] = mapped_column(BigInteger, default=0, server_default="0")
    content_hash: Mapped[str] = mapped_column(String(64), default="", server_default="")
    content: Mapped[dict[str, object]] = mapped_column(
        JSON, default=dict, server_default="{}"
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Asset(Base):
    __tablename__ = "assets"
    __table_args__ = (
        UniqueConstraint("object_key", name="uq_assets_object_key"),
        UniqueConstraint(
            "user_id",
            "notebook_id",
            "relative_path",
            name="uq_assets_user_notebook_relative_path",
        ),
        ForeignKeyConstraint(
            ["notebook_id", "user_id"],
            ["notebooks.id", "notebooks.user_id"],
            name="fk_assets_notebook_owner",
            ondelete="CASCADE",
        ),
        CheckConstraint("byte_size >= 0", name="ck_assets_byte_size"),
        CheckConstraint("length(sha256) = 64", name="ck_assets_sha256_length"),
        Index("ix_assets_user_id_notebook_id", "user_id", "notebook_id"),
        Index("ix_assets_user_id_sha256", "user_id", "sha256"),
    )

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    notebook_id: Mapped[str] = mapped_column(String(128))
    kind: Mapped[str] = mapped_column(String(32))
    original_filename: Mapped[str] = mapped_column(String(255))
    relative_path: Mapped[str] = mapped_column(String(1024))
    object_key: Mapped[str] = mapped_column(String(1024))
    content_type: Mapped[str] = mapped_column(String(255))
    byte_size: Mapped[int] = mapped_column(BigInteger)
    sha256: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class AssetUpload(Base):
    __tablename__ = "asset_uploads"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "asset_id", name="uq_asset_uploads_user_id_asset_id"
        ),
        UniqueConstraint(
            "staging_object_key", name="uq_asset_uploads_staging_object_key"
        ),
        ForeignKeyConstraint(
            ["notebook_id", "user_id"],
            ["notebooks.id", "notebooks.user_id"],
            name="fk_asset_uploads_notebook_owner",
            ondelete="CASCADE",
        ),
        CheckConstraint(
            "kind IN ('pdf', 'image', 'audio')", name="ck_asset_uploads_kind"
        ),
        CheckConstraint(
            "status IN ('pending', 'cancelled', 'completed', 'expired')",
            name="ck_asset_uploads_status",
        ),
        CheckConstraint(
            "expected_byte_size > 0", name="ck_asset_uploads_expected_byte_size"
        ),
        CheckConstraint(
            "length(expected_sha256) = 64",
            name="ck_asset_uploads_expected_sha256_length",
        ),
        Index(
            "ix_asset_uploads_user_notebook_status",
            "user_id",
            "notebook_id",
            "status",
        ),
        Index("ix_asset_uploads_status_expires_at", "status", "expires_at"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    device_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("devices.id", ondelete="SET NULL"), index=True
    )
    notebook_id: Mapped[str] = mapped_column(String(128))
    asset_id: Mapped[str] = mapped_column(String(128))
    kind: Mapped[str] = mapped_column(String(32))
    original_filename: Mapped[str] = mapped_column(String(255))
    relative_path: Mapped[str] = mapped_column(String(1024))
    staging_object_key: Mapped[str] = mapped_column(String(1024))
    content_type: Mapped[str] = mapped_column(String(255))
    expected_byte_size: Mapped[int] = mapped_column(BigInteger)
    expected_sha256: Mapped[str] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(
        String(32), default="pending", server_default="pending"
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    upload_url_expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    staging_deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cleanup_attempts: Mapped[int] = mapped_column(default=0, server_default="0")
    last_cleanup_error: Mapped[str | None] = mapped_column(String(512))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class AssetGarbageCollectionCandidate(Base):
    __tablename__ = "asset_gc_candidates"
    __table_args__ = (
        CheckConstraint(
            "reason = 'orphan_final_object'", name="ck_asset_gc_candidates_reason"
        ),
        CheckConstraint(
            "status IN ('pending', 'protected', 'deleted')",
            name="ck_asset_gc_candidates_status",
        ),
        CheckConstraint(
            "delete_attempts >= 0", name="ck_asset_gc_candidates_delete_attempts"
        ),
        Index(
            "ix_asset_gc_candidates_status_eligible_after",
            "status",
            "eligible_after",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    object_key: Mapped[str] = mapped_column(String(1024), unique=True)
    reason: Mapped[str] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(
        String(32), default="pending", server_default="pending"
    )
    first_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    eligible_after: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    last_checked_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    delete_attempts: Mapped[int] = mapped_column(default=0, server_default="0")
    last_error: Mapped[str | None] = mapped_column(String(512))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class SyncChange(Base):
    __tablename__ = "sync_changes"
    __table_args__ = (
        CheckConstraint(
            "resource_type IN "
            "('folder', 'notebook', 'page', 'infinite_canvas', 'asset', "
            "'conflict', 'tombstone')",
            name="ck_sync_changes_resource_type",
        ),
        CheckConstraint(
            "operation IN ('upsert', 'delete')",
            name="ck_sync_changes_operation",
        ),
        CheckConstraint(
            "revision IS NULL OR revision >= 0",
            name="ck_sync_changes_revision",
        ),
        CheckConstraint(
            "content_hash IS NULL OR length(content_hash) = 64",
            name="ck_sync_changes_content_hash_length",
        ),
        CheckConstraint(
            "(operation = 'upsert' AND payload IS NOT NULL) OR "
            "(operation = 'delete' AND payload IS NULL)",
            name="ck_sync_changes_operation_payload",
        ),
        Index("ix_sync_changes_user_sequence", "user_id", "sequence"),
    )

    sequence: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        Identity(),
        primary_key=True,
    )
    change_id: Mapped[UUID] = mapped_column(default=uuid4, unique=True)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    device_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("devices.id", ondelete="SET NULL"), index=True
    )
    resource_type: Mapped[str] = mapped_column(String(32))
    resource_id: Mapped[str] = mapped_column(String(128))
    operation: Mapped[str] = mapped_column(String(16))
    revision: Mapped[int | None] = mapped_column(BigInteger)
    content_hash: Mapped[str | None] = mapped_column(String(64))
    payload: Mapped[dict[str, object] | None] = mapped_column(JSON(none_as_null=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class SyncCommit(Base):
    __tablename__ = "sync_commits"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "device_id",
            "idempotency_key",
            name="uq_sync_commits_user_device_key",
        ),
        CheckConstraint(
            "length(request_hash) = 64",
            name="ck_sync_commits_request_hash_length",
        ),
        Index("ix_sync_commits_user_device", "user_id", "device_id"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    device_id: Mapped[UUID] = mapped_column(
        ForeignKey("devices.id", ondelete="CASCADE"), index=True
    )
    idempotency_key: Mapped[str] = mapped_column(String(128))
    request_hash: Mapped[str] = mapped_column(String(64))
    response_payload: Mapped[dict[str, object]] = mapped_column(
        JSON, default=dict, server_default="{}"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Conflict(Base):
    __tablename__ = "conflicts"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "copy_resource_id",
            name="uq_conflicts_user_copy_resource",
        ),
        CheckConstraint(
            "resource_type IN ('notebook', 'page')",
            name="ck_conflicts_resource_type",
        ),
        CheckConstraint("base_revision >= 0", name="ck_conflicts_base_revision"),
        CheckConstraint("current_revision >= 0", name="ck_conflicts_current_revision"),
        CheckConstraint(
            "length(submitted_content_hash) = 64",
            name="ck_conflicts_submitted_content_hash_length",
        ),
        CheckConstraint(
            "(current_revision = 0 AND current_content_hash = '') OR "
            "(current_revision > 0 AND length(current_content_hash) = 64)",
            name="ck_conflicts_current_content_version",
        ),
        CheckConstraint(
            "status IN ('pending', 'resolved')",
            name="ck_conflicts_status",
        ),
        CheckConstraint(
            "resolution IS NULL OR resolution IN "
            "('keep_original', 'use_conflict', 'keep_both')",
            name="ck_conflicts_resolution",
        ),
        CheckConstraint(
            "(status = 'pending' AND resolution IS NULL AND resolved_at IS NULL) OR "
            "(status = 'resolved' AND resolution IS NOT NULL "
            "AND resolved_at IS NOT NULL)",
            name="ck_conflicts_resolution_state",
        ),
        Index(
            "ix_conflicts_user_status_created",
            "user_id",
            "status",
            "created_at",
        ),
        Index(
            "ix_conflicts_user_resource",
            "user_id",
            "resource_type",
            "original_resource_id",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    resource_type: Mapped[str] = mapped_column(String(32))
    original_resource_id: Mapped[str] = mapped_column(String(128))
    copy_resource_id: Mapped[str] = mapped_column(String(128))
    copy_display_name: Mapped[str] = mapped_column(String(350))
    base_revision: Mapped[int] = mapped_column(BigInteger)
    current_revision: Mapped[int] = mapped_column(BigInteger)
    submitted_content_hash: Mapped[str] = mapped_column(String(64))
    submitted_content: Mapped[dict[str, object]] = mapped_column(JSON)
    current_content_hash: Mapped[str] = mapped_column(String(64))
    current_content: Mapped[dict[str, object]] = mapped_column(JSON)
    source_device_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("devices.id", ondelete="SET NULL"), index=True
    )
    status: Mapped[str] = mapped_column(
        String(32), default="pending", server_default="pending"
    )
    resolution: Mapped[str | None] = mapped_column(String(32))
    resolved_by_device_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("devices.id", ondelete="SET NULL"), index=True
    )
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Tombstone(Base):
    __tablename__ = "tombstones"
    __table_args__ = (
        CheckConstraint(
            "resource_type IN ('notebook', 'page', 'infinite_canvas')",
            name="ck_tombstones_resource_type",
        ),
        CheckConstraint("base_revision >= 0", name="ck_tombstones_base_revision"),
        CheckConstraint(
            "resource_revision >= 0", name="ck_tombstones_resource_revision"
        ),
        CheckConstraint(
            "deleted_revision IS NULL OR deleted_revision > 0",
            name="ck_tombstones_deleted_revision",
        ),
        CheckConstraint(
            "length(content_hash) = 64",
            name="ck_tombstones_content_hash_length",
        ),
        CheckConstraint(
            "state IN ('active', 'restored')",
            name="ck_tombstones_state",
        ),
        CheckConstraint(
            "conflict_kind IS NULL OR conflict_kind IN "
            "('delete_after_edit', 'edit_after_delete')",
            name="ck_tombstones_conflict_kind",
        ),
        CheckConstraint(
            "resolution IS NULL OR resolution IN "
            "('restored_snapshot', 'preserved_edit')",
            name="ck_tombstones_resolution",
        ),
        CheckConstraint(
            "(state = 'active' AND resolution IS NULL AND restored_at IS NULL) OR "
            "(state = 'restored' AND resolution IS NOT NULL "
            "AND restored_at IS NOT NULL)",
            name="ck_tombstones_state_resolution",
        ),
        Index(
            "uq_tombstones_active_resource",
            "user_id",
            "resource_type",
            "resource_id",
            unique=True,
            postgresql_where=text("state = 'active'"),
            sqlite_where=text("state = 'active'"),
        ),
        Index(
            "ix_tombstones_user_state_created",
            "user_id",
            "state",
            "created_at",
        ),
        Index(
            "ix_tombstones_user_resource",
            "user_id",
            "resource_type",
            "resource_id",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    resource_type: Mapped[str] = mapped_column(String(32))
    resource_id: Mapped[str] = mapped_column(String(128))
    base_revision: Mapped[int] = mapped_column(BigInteger)
    resource_revision: Mapped[int] = mapped_column(BigInteger)
    deleted_revision: Mapped[int | None] = mapped_column(BigInteger)
    content_hash: Mapped[str] = mapped_column(String(64))
    content: Mapped[dict[str, object]] = mapped_column(JSON)
    deleted_by_device_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("devices.id", ondelete="SET NULL"), index=True
    )
    deleted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    state: Mapped[str] = mapped_column(
        String(32), default="active", server_default="active"
    )
    conflict_kind: Mapped[str | None] = mapped_column(String(32))
    resolution: Mapped[str | None] = mapped_column(String(32))
    conflicting_device_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("devices.id", ondelete="SET NULL"), index=True
    )
    restored_by_device_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("devices.id", ondelete="SET NULL"), index=True
    )
    restored_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ContentRevision(Base):
    __tablename__ = "revisions"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "resource_type",
            "resource_id",
            "revision",
            name="uq_revisions_resource_revision",
        ),
        CheckConstraint(
            "resource_type IN ('notebook', 'page', 'infinite_canvas')",
            name="ck_revisions_resource_type",
        ),
        CheckConstraint("revision > 0", name="ck_revisions_revision"),
        CheckConstraint(
            "length(content_hash) = 64", name="ck_revisions_content_hash_length"
        ),
        Index(
            "ix_revisions_user_resource",
            "user_id",
            "resource_type",
            "resource_id",
            "revision",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    resource_type: Mapped[str] = mapped_column(String(32))
    resource_id: Mapped[str] = mapped_column(String(128))
    revision: Mapped[int] = mapped_column(BigInteger)
    content_hash: Mapped[str] = mapped_column(String(64))
    content: Mapped[dict[str, object]] = mapped_column(JSON)
    device_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("devices.id", ondelete="SET NULL"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
