"""Add versioned agreements and retryable account deletion.

Revision ID: 20260831_0016
Revises: 20260810_0015
Create Date: 2026-08-31
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260831_0016"
down_revision: str | None = "20260810_0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("privacy_policy_version", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("terms_version", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("agreements_accepted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_table(
        "account_deletion_requests",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column(
            "status",
            sa.String(length=16),
            server_default="pending",
            nullable=False,
        ),
        sa.Column("object_keys", sa.JSON(), nullable=False),
        sa.Column("attempts", sa.Integer(), server_default="0", nullable=False),
        sa.Column("last_error", sa.String(length=512), nullable=True),
        sa.Column(
            "requested_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "attempts >= 0", name="ck_account_deletion_requests_attempts"
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'completed')",
            name="ck_account_deletion_requests_status",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_account_deletion_requests_status_requested",
        "account_deletion_requests",
        ["status", "requested_at"],
    )
    op.create_index(
        "ix_account_deletion_requests_user_id",
        "account_deletion_requests",
        ["user_id"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_account_deletion_requests_user_id",
        table_name="account_deletion_requests",
    )
    op.drop_index(
        "ix_account_deletion_requests_status_requested",
        table_name="account_deletion_requests",
    )
    op.drop_table("account_deletion_requests")
    op.drop_column("users", "agreements_accepted_at")
    op.drop_column("users", "terms_version")
    op.drop_column("users", "privacy_policy_version")
