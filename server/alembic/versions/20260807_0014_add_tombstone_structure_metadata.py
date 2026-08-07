"""Add page structure metadata to tombstones.

Revision ID: 20260807_0014
Revises: 20260807_0013
Create Date: 2026-08-07
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260807_0014"
down_revision: str | None = "20260807_0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "tombstones",
        sa.Column(
            "structure_metadata",
            sa.JSON(),
            server_default="{}",
            nullable=False,
        ),
    )
    op.drop_constraint("uq_pages_notebook_owner_position", "pages", type_="unique")
    op.create_index(
        "uq_pages_active_notebook_owner_position",
        "pages",
        ["notebook_id", "user_id", "position"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
        sqlite_where=sa.text("deleted_at IS NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_pages_active_notebook_owner_position", table_name="pages")
    op.create_unique_constraint(
        "uq_pages_notebook_owner_position",
        "pages",
        ["notebook_id", "user_id", "position"],
    )
    op.drop_column("tombstones", "structure_metadata")
