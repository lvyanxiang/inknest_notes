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
    Index,
    Integer,
    String,
    UniqueConstraint,
    false,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from inknest_server.db.base import Base


class Folder(Base):
    __tablename__ = "folders"
    __table_args__ = (Index("ix_folders_user_id_updated_at", "user_id", "updated_at"),)

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    name: Mapped[str] = mapped_column(String(200))
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
