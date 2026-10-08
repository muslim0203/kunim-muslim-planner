"""Request bodies for account deletion."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field, model_validator


class AccountDeleteRequest(BaseModel):
    """Confirms the deletion: the password again, or, for an account signed
    into with Google, a fresh Google ID token. Exactly one of the two."""

    model_config = ConfigDict(extra="forbid")

    password: str | None = Field(default=None, min_length=1, max_length=128)
    google_id_token: str | None = Field(default=None, min_length=1, max_length=4096)

    @model_validator(mode="after")
    def _exactly_one_proof(self) -> AccountDeleteRequest:
        if (self.password is None) == (self.google_id_token is None):
            raise ValueError("send exactly one of `password` or `google_id_token`")
        return self
