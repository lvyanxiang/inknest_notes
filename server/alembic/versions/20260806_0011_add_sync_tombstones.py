"""Add soft deletion, synchronization tombstones, and recovery metadata.

Revision ID: 20260806_0011
Revises: 20260806_0010
Create Date: 2026-08-06
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260806_0011"
down_revision: str | None = "20260806_0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "notebooks", sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "pages", sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "infinite_canvases",
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )

    op.create_table(
        "tombstones",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("resource_type", sa.String(length=32), nullable=False),
        sa.Column("resource_id", sa.String(length=128), nullable=False),
        sa.Column("base_revision", sa.BigInteger(), nullable=False),
        sa.Column("resource_revision", sa.BigInteger(), nullable=False),
        sa.Column("deleted_revision", sa.BigInteger(), nullable=True),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        sa.Column("content", sa.JSON(), nullable=False),
        sa.Column("deleted_by_device_id", sa.Uuid(), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "state", sa.String(length=32), server_default="active", nullable=False
        ),
        sa.Column("conflict_kind", sa.String(length=32), nullable=True),
        sa.Column("resolution", sa.String(length=32), nullable=True),
        sa.Column("conflicting_device_id", sa.Uuid(), nullable=True),
        sa.Column("restored_by_device_id", sa.Uuid(), nullable=True),
        sa.Column("restored_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint("base_revision >= 0", name="ck_tombstones_base_revision"),
        sa.CheckConstraint(
            "resource_revision >= 0", name="ck_tombstones_resource_revision"
        ),
        sa.CheckConstraint(
            "deleted_revision IS NULL OR deleted_revision > 0",
            name="ck_tombstones_deleted_revision",
        ),
        sa.CheckConstraint(
            "length(content_hash) = 64",
            name="ck_tombstones_content_hash_length",
        ),
        sa.CheckConstraint(
            "resource_type IN ('notebook', 'page', 'infinite_canvas')",
            name="ck_tombstones_resource_type",
        ),
        sa.CheckConstraint(
            "state IN ('active', 'restored')", name="ck_tombstones_state"
        ),
        sa.CheckConstraint(
            "conflict_kind IS NULL OR conflict_kind IN "
            "('delete_after_edit', 'edit_after_delete')",
            name="ck_tombstones_conflict_kind",
        ),
        sa.CheckConstraint(
            "resolution IS NULL OR resolution IN "
            "('restored_snapshot', 'preserved_edit')",
            name="ck_tombstones_resolution",
        ),
        sa.CheckConstraint(
            "(state = 'active' AND resolution IS NULL AND restored_at IS NULL) OR "
            "(state = 'restored' AND resolution IS NOT NULL "
            "AND restored_at IS NOT NULL)",
            name="ck_tombstones_state_resolution",
        ),
        sa.ForeignKeyConstraint(
            ["conflicting_device_id"], ["devices.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["deleted_by_device_id"], ["devices.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["restored_by_device_id"], ["devices.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_tombstones_user_id"), "tombstones", ["user_id"], unique=False
    )
    op.create_index(
        op.f("ix_tombstones_deleted_by_device_id"),
        "tombstones",
        ["deleted_by_device_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_tombstones_conflicting_device_id"),
        "tombstones",
        ["conflicting_device_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_tombstones_restored_by_device_id"),
        "tombstones",
        ["restored_by_device_id"],
        unique=False,
    )
    op.create_index(
        "uq_tombstones_active_resource",
        "tombstones",
        ["user_id", "resource_type", "resource_id"],
        unique=True,
        postgresql_where=sa.text("state = 'active'"),
    )
    op.create_index(
        "ix_tombstones_user_state_created",
        "tombstones",
        ["user_id", "state", "created_at"],
        unique=False,
    )
    op.create_index(
        "ix_tombstones_user_resource",
        "tombstones",
        ["user_id", "resource_type", "resource_id"],
        unique=False,
    )

    op.drop_constraint("ck_sync_changes_resource_type", "sync_changes", type_="check")
    op.create_check_constraint(
        "ck_sync_changes_resource_type",
        "sync_changes",
        "resource_type IN "
        "('folder', 'notebook', 'page', 'infinite_canvas', 'asset', "
        "'conflict', 'tombstone')",
    )


def downgrade() -> None:
    op.drop_constraint("ck_sync_changes_resource_type", "sync_changes", type_="check")
    op.create_check_constraint(
        "ck_sync_changes_resource_type",
        "sync_changes",
        "resource_type IN "
        "('folder', 'notebook', 'page', 'infinite_canvas', 'asset', 'conflict')",
    )

    op.drop_index("ix_tombstones_user_resource", table_name="tombstones")
    op.drop_index("ix_tombstones_user_state_created", table_name="tombstones")
    op.drop_index("uq_tombstones_active_resource", table_name="tombstones")
    op.drop_index(op.f("ix_tombstones_restored_by_device_id"), table_name="tombstones")
    op.drop_index(op.f("ix_tombstones_conflicting_device_id"), table_name="tombstones")
    op.drop_index(op.f("ix_tombstones_deleted_by_device_id"), table_name="tombstones")
    op.drop_index(op.f("ix_tombstones_user_id"), table_name="tombstones")
    op.drop_table("tombstones")

    op.drop_column("infinite_canvases", "deleted_at")
    op.drop_column("pages", "deleted_at")
    op.drop_column("notebooks", "deleted_at")
