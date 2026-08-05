"""create asset upload sessions

Revision ID: 20260805_0005
Revises: 20260805_0004
Create Date: 2026-08-05 18:39:58.717402
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260805_0005"
down_revision: str | None = "20260805_0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "asset_uploads",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.Uuid(), nullable=True),
        sa.Column("notebook_id", sa.String(length=128), nullable=False),
        sa.Column("asset_id", sa.String(length=128), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("original_filename", sa.String(length=255), nullable=False),
        sa.Column("object_key", sa.String(length=1024), nullable=False),
        sa.Column("content_type", sa.String(length=255), nullable=False),
        sa.Column("expected_byte_size", sa.BigInteger(), nullable=False),
        sa.Column("expected_sha256", sa.String(length=64), nullable=False),
        sa.Column(
            "status",
            sa.String(length=32),
            server_default="pending",
            nullable=False,
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("upload_url_expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "kind IN ('pdf', 'image', 'audio')", name="ck_asset_uploads_kind"
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'cancelled', 'completed', 'expired')",
            name="ck_asset_uploads_status",
        ),
        sa.CheckConstraint(
            "expected_byte_size > 0", name="ck_asset_uploads_expected_byte_size"
        ),
        sa.CheckConstraint(
            "length(expected_sha256) = 64",
            name="ck_asset_uploads_expected_sha256_length",
        ),
        sa.ForeignKeyConstraint(["device_id"], ["devices.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(
            ["notebook_id", "user_id"],
            ["notebooks.id", "notebooks.user_id"],
            name="fk_asset_uploads_notebook_owner",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("object_key", name="uq_asset_uploads_object_key"),
        sa.UniqueConstraint(
            "user_id", "asset_id", name="uq_asset_uploads_user_id_asset_id"
        ),
    )
    op.create_index(
        op.f("ix_asset_uploads_device_id"),
        "asset_uploads",
        ["device_id"],
        unique=False,
    )
    op.create_index(
        "ix_asset_uploads_status_expires_at",
        "asset_uploads",
        ["status", "expires_at"],
        unique=False,
    )
    op.create_index(
        op.f("ix_asset_uploads_user_id"),
        "asset_uploads",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "ix_asset_uploads_user_notebook_status",
        "asset_uploads",
        ["user_id", "notebook_id", "status"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_asset_uploads_user_notebook_status", table_name="asset_uploads")
    op.drop_index(op.f("ix_asset_uploads_user_id"), table_name="asset_uploads")
    op.drop_index("ix_asset_uploads_status_expires_at", table_name="asset_uploads")
    op.drop_index(op.f("ix_asset_uploads_device_id"), table_name="asset_uploads")
    op.drop_table("asset_uploads")
