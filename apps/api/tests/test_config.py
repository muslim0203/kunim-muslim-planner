from __future__ import annotations

from app.core.config import Settings


def test_settings_defaults() -> None:
    settings = Settings(_env_file=None)
    assert settings.ENV == "dev"
    assert settings.ACCESS_TOKEN_TTL_MIN == 15
    assert settings.REFRESH_TOKEN_TTL_DAYS == 30
    assert settings.ADMIN_ENABLED is False


def test_settings_load_from_env_vars(monkeypatch) -> None:
    monkeypatch.setenv("ENV", "staging")
    monkeypatch.setenv("DEBUG", "false")
    monkeypatch.setenv("JWT_SECRET", "test-secret")
    monkeypatch.setenv("ACCESS_TOKEN_TTL_MIN", "30")
    monkeypatch.setenv("CORS_ORIGINS", "https://a.example.com,https://b.example.com")
    monkeypatch.setenv("ADMIN_ENABLED", "true")

    settings = Settings(_env_file=None)

    assert settings.ENV == "staging"
    assert settings.DEBUG is False
    assert settings.JWT_SECRET == "test-secret"
    assert settings.ACCESS_TOKEN_TTL_MIN == 30
    assert settings.CORS_ORIGINS == ["https://a.example.com", "https://b.example.com"]
    assert settings.ADMIN_ENABLED is True
