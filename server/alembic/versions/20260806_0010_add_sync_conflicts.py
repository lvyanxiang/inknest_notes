"""Add synchronization conflicts and conflict-copy ancestry.

Revision ID: 20260806_0010
Revises: 20260806_0009
Create Date: 2026-08-06
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260806_0010"
down_revision: str | None = "20260806_0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "notebooks", sa.Column("conflict_of", sa.String(length=128), nullable=True)
    )
    op.create_foreign_key(
        "fk_notebooks_conflict_origin_owner",
        "notebooks",
        "notebooks",
        ["conflict_of", "user_id"],
        ["id", "user_id"],
    )
    op.add_column(
        "pages", sa.Column("conflict_of", sa.String(length=128), nullable=True)
    )
    op.create_foreign_key(
        "fk_pages_conflict_origin_owner",
        "pages",
        "pages",
        ["conflict_of", "user_id"],
        ["id", "user_id"],
    )

    op.create_table(
        "conflicts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("resource_type", sa.String(length=32), nullable=False),
        sa.Column("original_resource_id", sa.String(length=128), nullable=False),
        sa.Column("copy_resource_id", sa.String(length=128), nullable=False),
        sa.Column("copy_display_name", sa.String(length=350), nullable=False),
        sa.Column("base_revision", sa.BigInteger(), nullable=False),
        sa.Column("current_revision", sa.BigInteger(), nullable=False),
        sa.Column("submitted_content_hash", sa.String(length=64), nullable=False),
        sa.Column("submitted_content", sa.JSON(), nullable=False),
        sa.Column("current_content_hash", sa.String(length=64), nullable=False),
        sa.Column("current_content", sa.JSON(), nullable=False),
        sa.Column("source_device_id", sa.Uuid(), nullable=True),
        sa.Column(
            "status",
            sa.String(length=32),
            server_default="pending",
            nullable=False,
        ),
        sa.Column("resolution", sa.String(length=32), nullable=True),
        sa.Column("resolved_by_device_id", sa.Uuid(), nullable=True),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint("base_revision >= 0", name="ck_conflicts_base_revision"),
        sa.CheckConstraint(
            "current_revision >= 0", name="ck_conflicts_current_revision"
        ),
        sa.CheckConstraint(
            "(current_revision = 0 AND current_content_hash = '') OR "
            "(current_revision > 0 AND length(current_content_hash) = 64)",
            name="ck_conflicts_current_content_version",
        ),
        sa.CheckConstraint(
            "length(submitted_content_hash) = 64",
            name="ck_conflicts_submitted_content_hash_length",
        ),
        sa.CheckConstraint(
            "resolution IS NULL OR resolution IN "
            "('keep_original', 'use_conflict', 'keep_both')",
            name="ck_conflicts_resolution",
        ),
        sa.CheckConstraint(
            "(status = 'pending' AND resolution IS NULL AND resolved_at IS NULL) OR "
            "(status = 'resolved' AND resolution IS NOT NULL "
            "AND resolved_at IS NOT NULL)",
            name="ck_conflicts_resolution_state",
        ),
        sa.CheckConstraint(
            "resource_type IN ('notebook', 'page')",
            name="ck_conflicts_resource_type",
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'resolved')", name="ck_conflicts_status"
        ),
        sa.ForeignKeyConstraint(
            ["resolved_by_device_id"], ["devices.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["source_device_id"], ["devices.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "copy_resource_id",
            name="uq_conflicts_user_copy_resource",
        ),
    )
    op.create_index(
        op.f("ix_conflicts_user_id"), "conflicts", ["user_id"], unique=False
    )
    op.create_index(
        op.f("ix_conflicts_source_device_id"),
        "conflicts",
        ["source_device_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_conflicts_resolved_by_device_id"),
        "conflicts",
        ["resolved_by_device_id"],
        unique=False,
    )
    op.create_index(
        "ix_conflicts_user_status_created",
        "conflicts",
        ["user_id", "status", "created_at"],
        unique=False,
    )
    op.create_index(
        "ix_conflicts_user_resource",
        "conflicts",
        ["user_id", "resource_type", "original_resource_id"],
        unique=False,
    )

    op.drop_constraint("ck_sync_changes_resource_type", "sync_changes", type_="check")
    op.create_check_constraint(
        "ck_sync_changes_resource_type",
        "sync_changes",
        "resource_type IN "
        "('folder', 'notebook', 'page', 'infinite_canvas', 'asset', 'conflict')",
    )


def downgrade() -> None:
    op.drop_constraint("ck_sync_changes_resource_type", "sync_changes", type_="check")
    op.create_check_constraint(
        "ck_sync_changes_resource_type",
        "sync_changes",
        "resource_type IN ('folder', 'notebook', 'page', 'infinite_canvas', 'asset')",
    )

    op.drop_index("ix_conflicts_user_resource", table_name="conflicts")
    op.drop_index("ix_conflicts_user_status_created", table_name="conflicts")
    op.drop_index(op.f("ix_conflicts_resolved_by_device_id"), table_name="conflicts")
    op.drop_index(op.f("ix_conflicts_source_device_id"), table_name="conflicts")
    op.drop_index(op.f("ix_conflicts_user_id"), table_name="conflicts")
    op.drop_table("conflicts")

    op.drop_constraint("fk_pages_conflict_origin_owner", "pages", type_="foreignkey")
    op.drop_column("pages", "conflict_of")
    op.drop_constraint(
        "fk_notebooks_conflict_origin_owner", "notebooks", type_="foreignkey"
    )
    op.drop_column("notebooks", "conflict_of")
