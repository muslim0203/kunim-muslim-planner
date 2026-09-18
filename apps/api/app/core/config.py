"""Application settings, loaded from environment variables / .env file."""

from __future__ import annotations

from functools import lru_cache
from typing import Annotated, Literal

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    """Central configuration object.

    All values can be overridden via environment variables or a `.env` file
    in the working directory. See `.env.example` for the full list.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    ENV: Literal["dev", "staging", "prod"] = "dev"

    # Secure by default. `DEBUG` is not cosmetic: it is passed to `FastAPI(...)`,
    # where Starlette's ServerErrorMiddleware renders a traceback for any
    # unhandled exception, and `core.errors` puts `str(exc)` in the response
    # body instead of "Internal server error". A production deploy that simply
    # forgot to set it therefore leaked internals -- which it did, visibly: a
    # cross-user `batch_id` collision returned a full Python traceback.
    #
    # Left unset it follows `ENV`, so a developer still gets tracebacks
    # locally without anyone having to remember a flag.
    DEBUG: bool = False

    DATABASE_URL: str = "postgresql+asyncpg://kunim:kunim@localhost:5432/kunim"
    REDIS_URL: str = "redis://localhost:6379/0"

    JWT_SECRET: str = "change-me-in-production"
    # AES-256-GCM key for EncryptedText columns (plan section 11,
    # `app.db.types`): the base64 encoding of exactly 32 random bytes. With the
    # placeholder, ENV=dev falls back to a public deterministic dev key and
    # every other ENV refuses to start. Versioned: `FIELD_ENC_KEY_VERSION` is
    # stamped into every ciphertext, and rotating the key requires a
    # re-encryption migration, never an in-place swap.
    FIELD_ENC_KEY: str = "change-me-in-production-32-bytes!"
    FIELD_ENC_KEY_VERSION: int = Field(default=1, ge=1)
    ACCESS_TOKEN_TTL_MIN: int = 15
    REFRESH_TOKEN_TTL_DAYS: int = 30

    CORS_ORIGINS: Annotated[list[str], NoDecode] = Field(default_factory=list)

    SENTRY_DSN: str | None = None

    ADMIN_ENABLED: bool = False

    APP_NAME: str = "KUNIM API"

    # Mail, used today only for password-reset codes. Without an API key
    # nothing is sent and the endpoints still answer -- the message is logged
    # as not sent (see `app.integrations.email`), so a deploy that forgot the
    # key is visible instead of silently swallowing resets.
    RESEND_API_KEY: str = ""
    EMAIL_FROM: str = "KUNIM <onboarding@resend.dev>"

    @model_validator(mode="after")
    def _debug_follows_env_unless_set(self) -> Settings:
        if "DEBUG" not in self.model_fields_set and self.ENV == "dev":
            # `object.__setattr__` would bypass validation; assigning through
            # the model keeps `validate_assignment` semantics if it is ever
            # switched on.
            self.DEBUG = True
        return self

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def _split_cors_origins(cls, value: object) -> object:
        """Allow a comma-separated string in addition to a JSON list."""
        if isinstance(value, str) and not value.strip().startswith("["):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value


JWT_SECRET_MIN_LENGTH = 32
_PLACEHOLDER_PREFIX = "change-me"


class InsecureSettingsError(RuntimeError):
    """A non-dev process was given a development secret.

    Messages name the setting, never its value.
    """


def check_jwt_secret(settings: Settings) -> None:
    """Refuse a placeholder, empty or short `JWT_SECRET` outside `ENV=dev`.

    Called from `app.main.create_app`, so a misconfigured staging/production
    process fails at startup instead of signing tokens with a public value.
    `ENV=dev` keeps accepting the placeholder. Not a field validator: plenty
    of code builds `Settings(ENV="prod")` just to inspect other fields.
    """
    if settings.ENV == "dev":
        return
    secret = settings.JWT_SECRET
    if (
        not secret.strip()
        or secret.strip().startswith(_PLACEHOLDER_PREFIX)
        or len(secret) < JWT_SECRET_MIN_LENGTH
    ):
        raise InsecureSettingsError(
            f"JWT_SECRET must be a random value of at least {JWT_SECRET_MIN_LENGTH} "
            f"characters (not the placeholder) when ENV={settings.ENV}; refusing to start"
        )


@lru_cache
def get_settings() -> Settings:
    """Return a cached Settings instance (construct once per process)."""
    return Settings()
