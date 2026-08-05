"""Add revisioned content storage.

Revision ID: 20260805_0004
Revises: 20260805_0003
Create Date: 2026-08-05
"""

import sqlalchemy as sa

from alembic import op

revision: str = "20260805_0004"
down_revision: str | None = "20260805_0003"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.create_table(
        "revisions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("resource_type", sa.String(length=32), nullable=False),
        sa.Column("resource_id", sa.String(length=128), nullable=False),
        sa.Column("revision", sa.BigInteger(), nullable=False),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        sa.Column("content", sa.JSON(), nullable=False),
        sa.Column("device_id", sa.Uuid(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "resource_type IN ('notebook', 'page', 'infinite_canvas')",
            name="ck_revisions_resource_type",
        ),
        sa.CheckConstraint(
            "length(content_hash) = 64", name="ck_revisions_content_hash_length"
        ),
        sa.CheckConstraint("revision > 0", name="ck_revisions_revision"),
        sa.ForeignKeyConstraint(
            ["device_id"],
            ["devices.id"],
            name="fk_revisions_device_id",
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name="fk_revisions_user_id",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_revisions"),
        sa.UniqueConstraint(
            "user_id",
            "resource_type",
            "resource_id",
            "revision",
            name="uq_revisions_resource_revision",
        ),
    )
    op.create_index(
        op.f("ix_revisions_device_id"), "revisions", ["device_id"], unique=False
    )
    op.create_index(
        op.f("ix_revisions_user_id"), "revisions", ["user_id"], unique=False
    )
    op.create_index(
        "ix_revisions_user_resource",
        "revisions",
        ["user_id", "resource_type", "resource_id", "revision"],
        unique=False,
    )
    op.add_column(
        "infinite_canvases",
        sa.Column("revision", sa.BigInteger(), server_default="0", nullable=False),
    )
    op.add_column(
        "infinite_canvases",
        sa.Column(
            "content_hash", sa.String(length=64), server_default="", nullable=False
        ),
    )
    op.add_column(
        "infinite_canvases",
        sa.Column("content", sa.JSON(), server_default="{}", nullable=False),
    )
    op.create_check_constraint(
        "ck_infinite_canvases_content_version",
        "infinite_canvases",
        "(revision = 0 AND content_hash = '') OR "
        "(revision > 0 AND length(content_hash) = 64)",
    )
    op.create_check_constraint(
        "ck_infinite_canvases_revision", "infinite_canvases", "revision >= 0"
    )
    op.add_column(
        "notebooks",
        sa.Column("revision", sa.BigInteger(), server_default="0", nullable=False),
    )
    op.add_column(
        "notebooks",
        sa.Column(
            "content_hash", sa.String(length=64), server_default="", nullable=False
        ),
    )
    op.add_column(
        "notebooks",
        sa.Column("content", sa.JSON(), server_default="{}", nullable=False),
    )
    op.create_check_constraint(
        "ck_notebooks_content_version",
        "notebooks",
        "(revision = 0 AND content_hash = '') OR "
        "(revision > 0 AND length(content_hash) = 64)",
    )
    op.create_check_constraint("ck_notebooks_revision", "notebooks", "revision >= 0")
    op.add_column(
        "pages",
        sa.Column("revision", sa.BigInteger(), server_default="0", nullable=False),
    )
    op.add_column(
        "pages",
        sa.Column(
            "content_hash", sa.String(length=64), server_default="", nullable=False
        ),
    )
    op.add_column(
        "pages", sa.Column("content", sa.JSON(), server_default="{}", nullable=False)
    )
    op.create_check_constraint(
        "ck_pages_content_version",
        "pages",
        "(revision = 0 AND content_hash = '') OR "
        "(revision > 0 AND length(content_hash) = 64)",
    )
    op.create_check_constraint("ck_pages_revision", "pages", "revision >= 0")


def downgrade() -> None:
    op.drop_constraint("ck_pages_revision", "pages", type_="check")
    op.drop_constraint("ck_pages_content_version", "pages", type_="check")
    op.drop_column("pages", "content")
    op.drop_column("pages", "content_hash")
    op.drop_column("pages", "revision")
    op.drop_constraint("ck_notebooks_revision", "notebooks", type_="check")
    op.drop_constraint("ck_notebooks_content_version", "notebooks", type_="check")
    op.drop_column("notebooks", "content")
    op.drop_column("notebooks", "content_hash")
    op.drop_column("notebooks", "revision")
    op.drop_constraint(
        "ck_infinite_canvases_revision", "infinite_canvases", type_="check"
    )
    op.drop_constraint(
        "ck_infinite_canvases_content_version", "infinite_canvases", type_="check"
    )
    op.drop_column("infinite_canvases", "content")
    op.drop_column("infinite_canvases", "content_hash")
    op.drop_column("infinite_canvases", "revision")
    op.drop_index("ix_revisions_user_resource", table_name="revisions")
    op.drop_index(op.f("ix_revisions_user_id"), table_name="revisions")
    op.drop_index(op.f("ix_revisions_device_id"), table_name="revisions")
    op.drop_table("revisions")
