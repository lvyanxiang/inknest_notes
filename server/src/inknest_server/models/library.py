from datetime import datetime
from uuid import UUID

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
