"""Production start-up: secret guards, and what start-up needs from outside.

* `JWT_SECRET` and `FIELD_ENC_KEY` placeholders are refused outside
  `ENV=dev`, by `create_app` (API) and by the arq worker's `startup`.
* With Railway-style URLs (`postgresql+asyncpg://...`, plain `redis://...`)
  and real secrets, `create_app` -- admin mount included -- and a `/health`
  request complete without opening a single socket: the database engine and
  the Redis client are both created lazily, on first real use.
"""

from __future__ import annotations

import base64
import os
import secrets
import socket
from collections.abc import Generator
from typing import Any

import pytest
from arq.connections import RedisSettings
from httpx import ASGITransport, AsyncClient

from app.core.config import (
    JWT_SECRET_MIN_LENGTH,
    InsecureSettingsError,
    Settings,
    check_jwt_secret,
)
from app.core.logging import configure_logging
from app.db.types import (
    DEV_FIELD_ENC_KEY,
    FieldCipher,
    FieldEncryptionConfigError,
    set_field_cipher,
)

GOOD_JWT_SECRET = secrets.token_urlsafe(48)
GOOD_FIELD_ENC_KEY = base64.b64encode(os.urandom(32)).decode()
RAILWAY_DATABASE_URL = (
    "postgresql+asyncpg://postgres:db-password@postgres.railway.internal:5432/railway"
)
RAILWAY_REDIS_URL = "redis://default:redis-password@redis.railway.internal:6379"


def _prod(**overrides: Any) -> Settings:
    values: dict[str, Any] = {
        "ENV": "prod",
        "JWT_SECRET": GOOD_JWT_SECRET,
        "FIELD_ENC_KEY": GOOD_FIELD_ENC_KEY,
        "DATABASE_URL": RAILWAY_DATABASE_URL,
        "REDIS_URL": RAILWAY_REDIS_URL,
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


@pytest.fixture
def isolated_startup_state() -> Generator[None, None, None]:
    """Undo the process-wide side effects of building an app with other settings."""
    from app.db.session import get_engine, get_sessionmaker

    get_engine.cache_clear()
    get_sessionmaker.cache_clear()
    set_field_cipher(None)
    try:
        yield
    finally:
        get_engine.cache_clear()
        get_sessionmaker.cache_clear()
        set_field_cipher(FieldCipher(DEV_FIELD_ENC_KEY))
        configure_logging(Settings(_env_file=None))


@pytest.fixture
def network_attempts(monkeypatch) -> list[str]:
    """Record (and refuse) every non-loopback DNS lookup or socket connect.

    Loopback stays allowed: the event loop itself talks to a local socket pair
    (notably on Windows), and no Railway service is on loopback.
    """
    attempts: list[str] = []
    loopback = {"127.0.0.1", "::1", "localhost"}
    real_getaddrinfo = socket.getaddrinfo
    real_create_connection = socket.create_connection
    real_connect = socket.socket.connect
    real_connect_ex = socket.socket.connect_ex

    def _host(address: Any) -> str:
        return str(address[0]) if isinstance(address, tuple) and address else str(address)

    def guarded(real: Any, host_of: Any) -> Any:
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            host = host_of(args)
            if host in loopback:
                return real(*args, **kwargs)
            attempts.append(host)
            raise OSError("network access is not allowed in this test")

        return wrapper

    monkeypatch.setattr(socket, "getaddrinfo", guarded(real_getaddrinfo, lambda a: str(a[0])))
    monkeypatch.setattr(
        socket, "create_connection", guarded(real_create_connection, lambda a: _host(a[0]))
    )
    monkeypatch.setattr(socket.socket, "connect", guarded(real_connect, lambda a: _host(a[1])))
    monkeypatch.setattr(
        socket.socket, "connect_ex", guarded(real_connect_ex, lambda a: _host(a[1]))
    )
    return attempts


def _use_settings(monkeypatch, settings: Settings) -> None:
    """Point every start-up `get_settings()` lookup at `settings`."""
    for target in (
        "app.main.get_settings",
        "app.db.types.get_settings",
        "app.db.session.get_settings",
        "app.jobs.worker.get_settings",
    ):
        monkeypatch.setattr(target, lambda: settings)


# --- JWT_SECRET guard -------------------------------------------------------------------


@pytest.mark.parametrize("env", ["staging", "prod"])
@pytest.mark.parametrize(
    "secret",
    [
        "change-me-in-production",
        "",
        "   ",
        "not-a-placeholder-but-short",
        "y" * (JWT_SECRET_MIN_LENGTH - 1),
        "change-me-" + "x" * 40,  # long, but still the placeholder
    ],
)
def test_non_dev_refuses_a_placeholder_empty_or_short_jwt_secret(env: str, secret: str) -> None:
    with pytest.raises(InsecureSettingsError) as excinfo:
        check_jwt_secret(_prod(ENV=env, JWT_SECRET=secret))
    if secret.strip():
        assert secret not in str(excinfo.value)  # the secret is never echoed


@pytest.mark.parametrize("secret", ["change-me-in-production", "", "short"])
def test_dev_keeps_accepting_the_placeholder_jwt_secret(secret: str) -> None:
    check_jwt_secret(Settings(_env_file=None, ENV="dev", JWT_SECRET=secret))


@pytest.mark.parametrize("secret", [GOOD_JWT_SECRET, "z" * JWT_SECRET_MIN_LENGTH])
def test_a_long_enough_jwt_secret_is_accepted_in_production(secret: str) -> None:
    check_jwt_secret(_prod(JWT_SECRET=secret))


def test_create_app_refuses_to_start_in_production_with_the_placeholder_jwt_secret(
    monkeypatch, isolated_startup_state
) -> None:
    from app import main

    _use_settings(monkeypatch, _prod(JWT_SECRET="change-me-in-production"))
    with pytest.raises(InsecureSettingsError):
        main.create_app()


def test_create_app_refuses_to_start_in_production_with_the_placeholder_field_key(
    monkeypatch, isolated_startup_state
) -> None:
    from app import main

    _use_settings(monkeypatch, _prod(FIELD_ENC_KEY="change-me-in-production-32-bytes!"))
    with pytest.raises(FieldEncryptionConfigError):
        main.create_app()


# --- Railway-style production start-up --------------------------------------------------


async def test_production_app_starts_with_railway_urls_without_any_network(
    monkeypatch, isolated_startup_state, network_attempts
) -> None:
    from app import main

    _use_settings(monkeypatch, _prod(ADMIN_ENABLED=True))
    app = main.create_app()

    # Included routers are wrapped in this FastAPI version, so read the API
    # surface from the OpenAPI schema (built in-process, no I/O).
    assert {"/sync/push", "/sync/pull", "/auth/login"} <= set(app.openapi()["paths"])
    mounts = {getattr(route, "path", None) for route in app.routes}
    assert "/admin" in mounts  # admin mount builds the engine object, still no connection

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as http:
        response = await http.get("/health")
    assert response.status_code == 200

    assert network_attempts == []


def test_railway_redis_url_parses_for_the_worker_without_connecting(network_attempts) -> None:
    settings = RedisSettings.from_dsn(RAILWAY_REDIS_URL)
    assert (settings.host, settings.port) == ("redis.railway.internal", 6379)
    assert network_attempts == []


async def test_worker_startup_refuses_a_placeholder_field_key_in_production(
    monkeypatch, isolated_startup_state
) -> None:
    from app.jobs import worker

    _use_settings(monkeypatch, _prod(FIELD_ENC_KEY="change-me-in-production-32-bytes!"))
    with pytest.raises(FieldEncryptionConfigError):
        await worker.startup({})


async def test_worker_startup_refuses_a_placeholder_jwt_secret_in_production(
    monkeypatch, isolated_startup_state
) -> None:
    from app.jobs import worker

    _use_settings(monkeypatch, _prod(JWT_SECRET="change-me-in-production"))
    with pytest.raises(InsecureSettingsError):
        await worker.startup({})


async def test_worker_startup_accepts_real_production_secrets_without_any_network(
    monkeypatch, isolated_startup_state, network_attempts
) -> None:
    from app.jobs import worker

    _use_settings(monkeypatch, _prod())
    await worker.startup({})
    assert network_attempts == []
