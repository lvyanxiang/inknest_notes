"""Add asset garbage collection tracking.

Revision ID: 20260806_0007
Revises: 20260806_0006
Create Date: 2026-08-06
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260806_0007"
down_revision: str | None = "20260806_0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "asset_gc_candidates",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("object_key", sa.String(length=1024), nullable=False),
        sa.Column("reason", sa.String(length=64), nullable=False),
        sa.Column(
            "status", sa.String(length=32), server_default="pending", nullable=False
        ),
        sa.Column("first_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("eligible_after", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_checked_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("delete_attempts", sa.Integer(), server_default="0", nullable=False),
        sa.Column("last_error", sa.String(length=512), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
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
            "reason = 'orphan_final_object'",
            name="ck_asset_gc_candidates_reason",
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'protected', 'deleted')",
            name="ck_asset_gc_candidates_status",
        ),
        sa.CheckConstraint(
            "delete_attempts >= 0",
            name="ck_asset_gc_candidates_delete_attempts",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("object_key"),
    )
    op.create_index(
        "ix_asset_gc_candidates_status_eligible_after",
        "asset_gc_candidates",
        ["status", "eligible_after"],
        unique=False,
    )
    op.add_column(
        "asset_uploads",
        sa.Column("staging_deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "asset_uploads",
        sa.Column("cleanup_attempts", sa.Integer(), server_default="0", nullable=False),
    )
    op.add_column(
        "asset_uploads",
        sa.Column("last_cleanup_error", sa.String(length=512), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("asset_uploads", "last_cleanup_error")
    op.drop_column("asset_uploads", "cleanup_attempts")
    op.drop_column("asset_uploads", "staging_deleted_at")
    op.drop_index(
        "ix_asset_gc_candidates_status_eligible_after",
        table_name="asset_gc_candidates",
    )
    op.drop_table("asset_gc_candidates")
