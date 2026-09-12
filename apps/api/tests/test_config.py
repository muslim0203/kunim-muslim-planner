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


def test_debug_is_off_outside_dev() -> None:
    """`DEBUG` must not be left on by forgetting a flag.

    It is passed to `FastAPI(...)`, so Starlette renders a traceback for any
    unhandled exception, and `core.errors` puts `str(exc)` in the response
    body. A production deploy that simply did not set it leaked internals.
    """
    for env in ("staging", "prod"):
        settings = Settings(_env_file=None, ENV=env)
        assert settings.DEBUG is False, f"DEBUG must default off for ENV={env}"


def test_debug_follows_dev_unless_set_explicitly() -> None:
    """Developers still get tracebacks locally without remembering a flag."""
    assert Settings(_env_file=None).DEBUG is True
    assert Settings(_env_file=None, ENV="dev").DEBUG is True

    # An explicit value always wins, in both directions.
    assert Settings(_env_file=None, ENV="dev", DEBUG=False).DEBUG is False
    assert Settings(_env_file=None, ENV="prod", DEBUG=True).DEBUG is True


def test_debug_env_var_overrides_the_env_default(monkeypatch) -> None:
    monkeypatch.setenv("ENV", "dev")
    monkeypatch.setenv("DEBUG", "false")
    assert Settings(_env_file=None).DEBUG is False
