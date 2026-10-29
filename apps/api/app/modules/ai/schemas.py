"""Wire shapes for `/ai/*`.

The request body is `app.ai.schemas.AnalystFacts`, re-exported here so the
router's imports stay local. It is defined over there because the agent and
the endpoint want exactly the same thing validated exactly once -- a separate
wire model would be a copy that drifts.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

from app.ai.schemas import AnalystFacts
from app.modules.ai.models import ProposalStatus

# The body of `POST /ai/analysis`. See the module docstring.
AnalysisRequest = AnalystFacts

__all__ = [
    "AnalysisRequest",
    "AnalystFacts",
    "ProposalOut",
    "ProposalStatusUpdate",
]


class ProposalOut(BaseModel):
    """A proposal as the app reads it."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    agent: str
    status: ProposalStatus
    payload: dict
    model: str | None = None
    created_at: datetime


class ProposalStatusUpdate(BaseModel):
    """What the user did with a proposal.

    `applied_diff` is what they changed before accepting -- free-form,
    because what "changed" means differs per agent, and the server only ever
    stores it. It is never read back into a decision here: the widget the
    user ends up with is created on their phone and arrives through sync.
    """

    model_config = ConfigDict(extra="forbid")

    status: Annotated[
        ProposalStatus,
        Field(description="accepted, modified or rejected"),
    ]
    applied_diff: dict | None = None
