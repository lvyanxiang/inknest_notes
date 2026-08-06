"""Add restorable notebook-relative paths to assets.

Revision ID: 20260806_0012
Revises: 20260806_0011
Create Date: 2026-08-06
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260806_0012"
down_revision: str | None = "20260806_0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "asset_uploads",
        sa.Column("relative_path", sa.String(length=1024), nullable=True),
    )
    op.add_column(
        "assets",
        sa.Column("relative_path", sa.String(length=1024), nullable=True),
    )

    # Assets created before this contract did not retain their original local
    # path. Give them a safe, collision-free recovery path; new uploads always
    # send the exact notebook-relative path used by their JSON references.
    op.execute(
        """
        UPDATE asset_uploads
        SET relative_path = CASE kind
            WHEN 'image' THEN 'assets/images/' || asset_id
            WHEN 'audio' THEN 'assets/audio/' || asset_id
            ELSE 'assets/pdfs/' || asset_id
        END
        WHERE relative_path IS NULL
        """
    )
    op.execute(
        """
        UPDATE assets
        SET relative_path = CASE kind
            WHEN 'image' THEN 'assets/images/' || id
            WHEN 'audio' THEN 'assets/audio/' || id
            ELSE 'assets/pdfs/' || id
        END
        WHERE relative_path IS NULL
        """
    )

    op.alter_column("asset_uploads", "relative_path", nullable=False)
    op.alter_column("assets", "relative_path", nullable=False)
    op.create_unique_constraint(
        "uq_assets_user_notebook_relative_path",
        "assets",
        ["user_id", "notebook_id", "relative_path"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_assets_user_notebook_relative_path",
        "assets",
        type_="unique",
    )
    op.drop_column("assets", "relative_path")
    op.drop_column("asset_uploads", "relative_path")
