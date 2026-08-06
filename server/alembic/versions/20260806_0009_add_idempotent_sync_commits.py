"""Add idempotent synchronization commits.

Revision ID: 20260806_0009
Revises: 20260806_0008
Create Date: 2026-08-06
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260806_0009"
down_revision: str | None = "20260806_0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "sync_commits",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.Uuid(), nullable=False),
        sa.Column("idempotency_key", sa.String(length=128), nullable=False),
        sa.Column("request_hash", sa.String(length=64), nullable=False),
        sa.Column("response_payload", sa.JSON(), server_default="{}", nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "length(request_hash) = 64",
            name="ck_sync_commits_request_hash_length",
        ),
        sa.ForeignKeyConstraint(
            ["device_id"],
            ["devices.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "device_id",
            "idempotency_key",
            name="uq_sync_commits_user_device_key",
        ),
    )
    op.create_index(
        op.f("ix_sync_commits_device_id"),
        "sync_commits",
        ["device_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_sync_commits_user_id"),
        "sync_commits",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "ix_sync_commits_user_device",
        "sync_commits",
        ["user_id", "device_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_sync_commits_user_device", table_name="sync_commits")
    op.drop_index(op.f("ix_sync_commits_user_id"), table_name="sync_commits")
    op.drop_index(op.f("ix_sync_commits_device_id"), table_name="sync_commits")
    op.drop_table("sync_commits")
