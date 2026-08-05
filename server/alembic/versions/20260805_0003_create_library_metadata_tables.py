"""Create library metadata tables.

Revision ID: 20260805_0003
Revises: 20260805_0002
Create Date: 2026-08-05
"""

import sqlalchemy as sa

from alembic import op

revision: str = "20260805_0003"
down_revision: str | None = "20260805_0002"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.create_table(
        "folders",
        sa.Column("id", sa.String(length=128), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
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
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name="fk_folders_user_id",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", "user_id", name="pk_folders"),
    )
    op.create_index("ix_folders_user_id", "folders", ["user_id"])
    op.create_index(
        "ix_folders_user_id_updated_at", "folders", ["user_id", "updated_at"]
    )

    op.create_table(
        "notebooks",
        sa.Column("id", sa.String(length=128), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("folder_id", sa.String(length=128), nullable=True),
        sa.Column("title", sa.String(length=300), nullable=False),
        sa.Column(
            "layout_mode",
            sa.String(length=32),
            server_default="paged",
            nullable=False,
        ),
        sa.Column(
            "is_archived",
            sa.Boolean(),
            server_default=sa.false(),
            nullable=False,
        ),
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
            "layout_mode IN ('paged', 'infiniteCanvas')",
            name="ck_notebooks_layout_mode",
        ),
        sa.ForeignKeyConstraint(
            ["folder_id", "user_id"],
            ["folders.id", "folders.user_id"],
            name="fk_notebooks_folder_owner",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name="fk_notebooks_user_id",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", "user_id", name="pk_notebooks"),
    )
    op.create_index("ix_notebooks_user_id", "notebooks", ["user_id"])
    op.create_index(
        "ix_notebooks_user_id_folder_id", "notebooks", ["user_id", "folder_id"]
    )
    op.create_index(
        "ix_notebooks_user_id_updated_at",
        "notebooks",
        ["user_id", "updated_at"],
    )

    op.create_table(
        "assets",
        sa.Column("id", sa.String(length=128), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("notebook_id", sa.String(length=128), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("original_filename", sa.String(length=255), nullable=False),
        sa.Column("object_key", sa.String(length=1024), nullable=False),
        sa.Column("content_type", sa.String(length=255), nullable=False),
        sa.Column("byte_size", sa.BigInteger(), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=False),
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
        sa.CheckConstraint("byte_size >= 0", name="ck_assets_byte_size"),
        sa.CheckConstraint("length(sha256) = 64", name="ck_assets_sha256_length"),
        sa.ForeignKeyConstraint(
            ["notebook_id", "user_id"],
            ["notebooks.id", "notebooks.user_id"],
            name="fk_assets_notebook_owner",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name="fk_assets_user_id",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", "user_id", name="pk_assets"),
        sa.UniqueConstraint("object_key", name="uq_assets_object_key"),
    )
    op.create_index("ix_assets_user_id", "assets", ["user_id"])
    op.create_index(
        "ix_assets_user_id_notebook_id", "assets", ["user_id", "notebook_id"]
    )
    op.create_index("ix_assets_user_id_sha256", "assets", ["user_id", "sha256"])

    op.create_table(
        "infinite_canvases",
        sa.Column("id", sa.String(length=128), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("notebook_id", sa.String(length=128), nullable=False),
        sa.Column(
            "background",
            sa.String(length=32),
            server_default="blank",
            nullable=False,
        ),
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
        sa.ForeignKeyConstraint(
            ["notebook_id", "user_id"],
            ["notebooks.id", "notebooks.user_id"],
            name="fk_infinite_canvases_notebook_owner",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name="fk_infinite_canvases_user_id",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", "user_id", name="pk_infinite_canvases"),
        sa.UniqueConstraint(
            "notebook_id",
            "user_id",
            name="uq_infinite_canvases_notebook_owner",
        ),
    )
    op.create_index("ix_infinite_canvases_user_id", "infinite_canvases", ["user_id"])
    op.create_index(
        "ix_infinite_canvases_user_id_notebook_id",
        "infinite_canvases",
        ["user_id", "notebook_id"],
    )

    op.create_table(
        "pages",
        sa.Column("id", sa.String(length=128), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("notebook_id", sa.String(length=128), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("width", sa.Float(), nullable=False),
        sa.Column("height", sa.Float(), nullable=False),
        sa.Column("coordinate_space_version", sa.JSON(), nullable=False),
        sa.Column(
            "rotation_quarter_turns",
            sa.Integer(),
            server_default="0",
            nullable=False,
        ),
        sa.Column(
            "template",
            sa.String(length=32),
            server_default="blank",
            nullable=False,
        ),
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
        sa.CheckConstraint("height > 0", name="ck_pages_height"),
        sa.CheckConstraint("position >= 0", name="ck_pages_position"),
        sa.CheckConstraint(
            "rotation_quarter_turns BETWEEN 0 AND 3",
            name="ck_pages_rotation_quarter_turns",
        ),
        sa.CheckConstraint("width > 0", name="ck_pages_width"),
        sa.ForeignKeyConstraint(
            ["notebook_id", "user_id"],
            ["notebooks.id", "notebooks.user_id"],
            name="fk_pages_notebook_owner",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name="fk_pages_user_id",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", "user_id", name="pk_pages"),
        sa.UniqueConstraint(
            "notebook_id",
            "user_id",
            "position",
            name="uq_pages_notebook_owner_position",
        ),
    )
    op.create_index("ix_pages_user_id", "pages", ["user_id"])
    op.create_index("ix_pages_user_id_notebook_id", "pages", ["user_id", "notebook_id"])


def downgrade() -> None:
    op.drop_index("ix_pages_user_id_notebook_id", table_name="pages")
    op.drop_index("ix_pages_user_id", table_name="pages")
    op.drop_table("pages")
    op.drop_index(
        "ix_infinite_canvases_user_id_notebook_id",
        table_name="infinite_canvases",
    )
    op.drop_index("ix_infinite_canvases_user_id", table_name="infinite_canvases")
    op.drop_table("infinite_canvases")
    op.drop_index("ix_assets_user_id_sha256", table_name="assets")
    op.drop_index("ix_assets_user_id_notebook_id", table_name="assets")
    op.drop_index("ix_assets_user_id", table_name="assets")
    op.drop_table("assets")
    op.drop_index("ix_notebooks_user_id_updated_at", table_name="notebooks")
    op.drop_index("ix_notebooks_user_id_folder_id", table_name="notebooks")
    op.drop_index("ix_notebooks_user_id", table_name="notebooks")
    op.drop_table("notebooks")
    op.drop_index("ix_folders_user_id_updated_at", table_name="folders")
    op.drop_index("ix_folders_user_id", table_name="folders")
    op.drop_table("folders")
