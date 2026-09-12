"""Application settings, loaded from environment variables / .env file."""

from __future__ import annotations

from functools import lru_cache
from typing import Annotated, Literal

from pydantic import Field, field_validator
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
    DEBUG: bool = True

    DATABASE_URL: str = "postgresql+asyncpg://kunim:kunim@localhost:5432/kunim"
    REDIS_URL: str = "redis://localhost:6379/0"

    JWT_SECRET: str = "change-me-in-production"
    # AES-256-GCM key for EncryptedText columns (plan section 11). Versioned:
    # rotating it requires a re-encryption migration, never an in-place swap.
    FIELD_ENC_KEY: str = "change-me-in-production-32-bytes!"
    ACCESS_TOKEN_TTL_MIN: int = 15
    REFRESH_TOKEN_TTL_DAYS: int = 30

    CORS_ORIGINS: Annotated[list[str], NoDecode] = Field(default_factory=list)

    SENTRY_DSN: str | None = None

    ADMIN_ENABLED: bool = False

    APP_NAME: str = "KUNIM API"

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def _split_cors_origins(cls, value: object) -> object:
        """Allow a comma-separated string in addition to a JSON list."""
        if isinstance(value, str) and not value.strip().startswith("["):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value


@lru_cache
def get_settings() -> Settings:
    """Return a cached Settings instance (construct once per process)."""
    return Settings()
