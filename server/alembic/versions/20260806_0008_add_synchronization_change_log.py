"""Add the synchronization change log.

Revision ID: 20260806_0008
Revises: 20260806_0007
Create Date: 2026-08-06
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260806_0008"
down_revision: str | None = "20260806_0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "sync_changes",
        sa.Column(
            "sequence",
            sa.BigInteger(),
            sa.Identity(always=False),
            nullable=False,
        ),
        sa.Column("change_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.Uuid(), nullable=True),
        sa.Column("resource_type", sa.String(length=32), nullable=False),
        sa.Column("resource_id", sa.String(length=128), nullable=False),
        sa.Column("operation", sa.String(length=16), nullable=False),
        sa.Column("revision", sa.BigInteger(), nullable=True),
        sa.Column("content_hash", sa.String(length=64), nullable=True),
        sa.Column("payload", sa.JSON(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "(operation = 'upsert' AND payload IS NOT NULL) OR "
            "(operation = 'delete' AND payload IS NULL)",
            name="ck_sync_changes_operation_payload",
        ),
        sa.CheckConstraint(
            "operation IN ('upsert', 'delete')",
            name="ck_sync_changes_operation",
        ),
        sa.CheckConstraint(
            "resource_type IN "
            "('folder', 'notebook', 'page', 'infinite_canvas', 'asset')",
            name="ck_sync_changes_resource_type",
        ),
        sa.CheckConstraint(
            "content_hash IS NULL OR length(content_hash) = 64",
            name="ck_sync_changes_content_hash_length",
        ),
        sa.CheckConstraint(
            "revision IS NULL OR revision >= 0",
            name="ck_sync_changes_revision",
        ),
        sa.ForeignKeyConstraint(
            ["device_id"],
            ["devices.id"],
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("sequence"),
        sa.UniqueConstraint("change_id"),
    )
    op.create_index(
        op.f("ix_sync_changes_device_id"),
        "sync_changes",
        ["device_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_sync_changes_user_id"),
        "sync_changes",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "ix_sync_changes_user_sequence",
        "sync_changes",
        ["user_id", "sequence"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_sync_changes_user_sequence", table_name="sync_changes")
    op.drop_index(op.f("ix_sync_changes_user_id"), table_name="sync_changes")
    op.drop_index(op.f("ix_sync_changes_device_id"), table_name="sync_changes")
    op.drop_table("sync_changes")
