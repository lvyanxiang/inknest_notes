"""Add revision metadata to folders.

Revision ID: 20260807_0013
Revises: 20260806_0012
Create Date: 2026-08-07
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260807_0013"
down_revision: str | None = "20260806_0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "folders",
        sa.Column("revision", sa.BigInteger(), server_default="0", nullable=False),
    )
    op.add_column(
        "folders",
        sa.Column(
            "content_hash", sa.String(length=64), server_default="", nullable=False
        ),
    )
    op.create_check_constraint("ck_folders_revision", "folders", "revision >= 0")
    op.create_check_constraint(
        "ck_folders_content_version",
        "folders",
        "(revision = 0 AND content_hash = '') OR "
        "(revision > 0 AND length(content_hash) = 64)",
    )


def downgrade() -> None:
    op.drop_constraint("ck_folders_content_version", "folders", type_="check")
    op.drop_constraint("ck_folders_revision", "folders", type_="check")
    op.drop_column("folders", "content_hash")
    op.drop_column("folders", "revision")
