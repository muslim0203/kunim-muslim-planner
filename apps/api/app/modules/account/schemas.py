"""Request bodies for account deletion."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class AccountDeleteRequest(BaseModel):
    """The account's password, entered again to confirm the deletion."""

    model_config = ConfigDict(extra="forbid")

    password: str = Field(min_length=1, max_length=128)
