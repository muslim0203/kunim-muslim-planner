"""friends, invite codes and the leaderboard opt-in

Revision ID: 0013_social
Revises: 0012_daily_scores
Create Date: 2026-09-18

Adds what the two boards need:

- `friendships`: one row per direction, so "my friends" is a single indexed
  lookup and unfriending is symmetric. The pair is unique.
- `friend_invites`: a short, single-use code with an expiry, shared out of
  band by its owner.
- `users.nickname`: the name shown on a board, unique so two people cannot
  claim the same one. Null until the user picks one.
- `users.leaderboard_opt_in`: false by default. The global board lists only
  users who turned it on *and* chose a nickname, so nobody is ever listed
  under a name they did not pick.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0013_social"
down_revision: str | None = "0012_daily_scores"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("nickname", sa.String(length=24), nullable=True))
    op.create_unique_constraint("uq_users_nickname", "users", ["nickname"])
    op.add_column(
        "users",
        sa.Column(
            "leaderboard_opt_in",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )

    op.create_table(
        "friendships",
        sa.Column("id", sa.Uuid(), nullable=False),
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
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("friend_id", sa.Uuid(), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_friendships")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_friendships_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["friend_id"],
            ["users.id"],
            name=op.f("fk_friendships_friend_id_users"),
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint("user_id", "friend_id", name="uq_friendships_pair"),
    )
    op.create_index("ix_friendships_user_id", "friendships", ["user_id"])

    op.create_table(
        "friend_invites",
        sa.Column("id", sa.Uuid(), nullable=False),
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
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("code", sa.String(length=16), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_by", sa.Uuid(), nullable=True),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_friend_invites")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_friend_invites_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["used_by"],
            ["users.id"],
            name=op.f("fk_friend_invites_used_by_users"),
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint("code", name="uq_friend_invites_code"),
    )
    op.create_index("ix_friend_invites_user_id", "friend_invites", ["user_id"])
    op.create_index("ix_friend_invites_code", "friend_invites", ["code"])


def downgrade() -> None:
    op.drop_index("ix_friend_invites_code", table_name="friend_invites")
    op.drop_index("ix_friend_invites_user_id", table_name="friend_invites")
    op.drop_table("friend_invites")

    op.drop_index("ix_friendships_user_id", table_name="friendships")
    op.drop_table("friendships")

    op.drop_column("users", "leaderboard_opt_in")
    op.drop_constraint("uq_users_nickname", "users", type_="unique")
    op.drop_column("users", "nickname")
