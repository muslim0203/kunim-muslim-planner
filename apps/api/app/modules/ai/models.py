"""What the server keeps about an AI call.

Two tables, and what is *not* in them is the point:

* `ai_proposals` holds what the model suggested. It is the only thing an
  agent can produce. Accepting one changes nothing here but its `status`;
  the widget itself is created on the phone and arrives later through
  ordinary sync, so the offline invariants (`ADR-0002`: local write and
  outbox in one transaction) are untouched. There is no code path on the
  server from a proposal to a user's `habits` row -- see rule 3 of
  `CLAUDE.md`.
* `ai_requests` holds what a call cost: counts and money, never content. No
  prompt, no answer, no widget title. The spend report needs tokens; it does
  not need the user's day (rule 7 of `CLAUDE.md`).

Neither is a sync table: both are server-owned records *about* the user's
data rather than part of it, so they carry no `server_version` and the
client reads them over `/ai/*` rather than through `/sync`.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from enum import StrEnum

from sqlalchemy import (
    JSON,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    func,
)
from sqlalchemy.dialects import postgresql
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import Timestamps

# JSONB on PostgreSQL, plain JSON elsewhere (SQLite in tests) -- the same
# pattern as `app.modules.habits.models`.
_JSONType = JSON().with_variant(postgresql.JSONB(), "postgresql")


class ProposalStatus(StrEnum):
    """Where a proposal stands.

    `modified` is distinct from `accepted` on purpose: a user who kept the
    suggestion but changed the amount told us something a plain yes did not,
    and the plan's quality metric reads that column.
    """

    proposed = "proposed"
    accepted = "accepted"
    modified = "modified"
    rejected = "rejected"


class AiProposal(Timestamps, Base):
    """One agent's answer, waiting for the user's yes or no."""

    __tablename__ = "ai_proposals"
    __table_args__ = (
        # The client asks for "my latest proposals", newest first.
        Index("ix_ai_proposals_user_id_created_at", "user_id", "created_at"),
    )

    # Server-generated, unlike the sync tables' client-generated ids: a
    # proposal is only ever created here.
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    # Which agent produced it (`analyst`, later `planner`, `coach`, ...). A
    # plain slug, not a database enum, so a new agent is a deploy and not a
    # migration.
    agent: Mapped[str] = mapped_column(String(32), nullable=False)

    payload: Mapped[dict] = mapped_column(_JSONType, nullable=False, default=dict)

    # Validated at the API boundary against `ProposalStatus`, kept as a
    # string in the column -- the same choice as `users.gender`, and it keeps
    # adding a status out of the enum-migration business.
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, default=ProposalStatus.proposed.value
    )

    # What the user actually did with it, when that differs from the
    # suggestion. Null until they accept or modify it.
    applied_diff: Mapped[dict | None] = mapped_column(_JSONType, nullable=True, default=None)

    # The model that produced it, for when a proposal has to be explained
    # after the fact.
    model: Mapped[str | None] = mapped_column(String(64), nullable=True, default=None)


class AiRequest(Base):
    """What one provider call cost. Counts and money only -- never content."""

    __tablename__ = "ai_requests"
    __table_args__ = (Index("ix_ai_requests_user_id_created_at", "user_id", "created_at"),)

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    agent: Mapped[str] = mapped_column(String(32), nullable=False)
    model: Mapped[str] = mapped_column(String(64), nullable=False)

    input_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    cache_read_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    # Kept beside the others because the first call of a cache window pays a
    # premium for these and the rest pay almost nothing: without the count,
    # a month's `cost_usd` cannot be explained.
    cache_write_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    # Micro-dollar precision: one analysis costs a fraction of a cent, and a
    # float would round a month of them into noise.
    cost_usd: Mapped[Decimal] = mapped_column(Numeric(12, 6), nullable=False, default=Decimal("0"))

    latency_ms: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    # `app.ai.safety` flag names, or `refused` / `unavailable` / `malformed`
    # when there was no answer. The list of what went wrong, without what
    # went wrong *in*.
    safety_flags: Mapped[list] = mapped_column(_JSONType, nullable=False, default=list)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
