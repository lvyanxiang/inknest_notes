"""Add a stable installation identity to devices.

Revision ID: 20260810_0015
Revises: 20260807_0014
Create Date: 2026-08-10
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260810_0015"
down_revision: str | None = "20260807_0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "devices",
        sa.Column("client_instance_id", sa.String(length=128), nullable=True),
    )
    op.create_unique_constraint(
        "uq_devices_user_client_instance_id",
        "devices",
        ["user_id", "client_instance_id"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_devices_user_client_instance_id",
        "devices",
        type_="unique",
    )
    op.drop_column("devices", "client_instance_id")
