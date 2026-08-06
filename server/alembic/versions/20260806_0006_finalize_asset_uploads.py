"""finalize asset uploads

Revision ID: 20260806_0006
Revises: 20260805_0005
Create Date: 2026-08-06 11:11:35.294667
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260806_0006"
down_revision: str | None = "20260805_0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.alter_column(
        "asset_uploads",
        "object_key",
        new_column_name="staging_object_key",
        existing_type=sa.String(length=1024),
        existing_nullable=False,
    )
    op.execute(
        "ALTER TABLE asset_uploads "
        "RENAME CONSTRAINT uq_asset_uploads_object_key "
        "TO uq_asset_uploads_staging_object_key"
    )
    op.add_column(
        "asset_uploads",
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("asset_uploads", "completed_at")
    op.execute(
        "ALTER TABLE asset_uploads "
        "RENAME CONSTRAINT uq_asset_uploads_staging_object_key "
        "TO uq_asset_uploads_object_key"
    )
    op.alter_column(
        "asset_uploads",
        "staging_object_key",
        new_column_name="object_key",
        existing_type=sa.String(length=1024),
        existing_nullable=False,
    )
