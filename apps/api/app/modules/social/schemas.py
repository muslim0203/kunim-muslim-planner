"""Wire shapes for `/social`.

What a board row may carry is deliberately narrow: an id, the name the user
chose to show, and their points. No email, ever -- a leaderboard is the one
place in the app where one user's data is shown to another.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class InviteOut(BaseModel):
    """A freshly minted invite code and when it stops working."""

    code: str
    expires_at: datetime


class InviteAccept(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: str = Field(min_length=4, max_length=16)


class BoardEntry(BaseModel):
    """One person on a board."""

    user_id: uuid.UUID

    # The name this user shows: their nickname, or the display name they
    # already share with friends. Null when they have chosen neither, and the
    # client shows its own placeholder rather than the server inventing one
    # in a language it does not know.
    name: str | None = None
    points_week: int
    points_total: int

    # True for the caller's own row.
    is_me: bool = False


class Board(BaseModel):
    """A board, best first, plus where the caller stands on it."""

    entries: list[BoardEntry]

    # The caller's position, 1-based, or null when they are not on it.
    my_rank: int | None = None
