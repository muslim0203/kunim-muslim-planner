"""Google sign-in: `/auth/google`, account linking and Google-confirmed deletion.

The verifier is tested on its own against tokens signed with a locally
generated RSA key standing in for Google's; the endpoint tests swap in a fake
verifier, so nothing here reaches the network.
"""

from __future__ import annotations

import time
from collections.abc import AsyncGenerator
from dataclasses import dataclass
from typing import Any

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.integrations.google_signin import (
    GoogleIdentity,
    GoogleIdTokenVerifier,
    GoogleSignInDisabled,
    InvalidGoogleToken,
    get_google_verifier,
)
from app.main import app
from app.modules.auth.models import UserIdentity
from app.modules.auth.ratelimit import RateLimiter, auth_rate_limit, set_rate_limiter
from app.modules.users.models import User

TEST_JWT_SECRET = "test-secret-key-that-is-comfortably-longer-than-32-bytes-ok!!"
CLIENT_ID = "kunim-web.apps.googleusercontent.com"
PASSWORD = "correct-horse-battery"


# --- the verifier ------------------------------------------------------------

_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_OTHER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


@dataclass
class _Key:
    key: Any


class _StaticKeys:
    """Stands in for Google's JWKS endpoint."""

    def get_signing_key_from_jwt(self, token: str) -> _Key:
        return _Key(_KEY.public_key())


def _token(key: Any = _KEY, **overrides: Any) -> str:
    now = int(time.time())
    claims: dict[str, Any] = {
        "iss": "https://accounts.google.com",
        "aud": CLIENT_ID,
        "sub": "1234567890",
        "email": "Aziza@Gmail.com",
        "email_verified": True,
        "iat": now,
        "exp": now + 3600,
    }
    claims.update(overrides)
    claims = {k: v for k, v in claims.items() if v is not None}
    return jwt.encode(claims, key, algorithm="RS256")


def _verifier(client_ids: list[str] | None = None) -> GoogleIdTokenVerifier:
    ids = [CLIENT_ID] if client_ids is None else client_ids
    return GoogleIdTokenVerifier(ids, key_source=_StaticKeys())


async def test_verifier_accepts_a_valid_token_and_normalises_the_email() -> None:
    identity = await _verifier().verify(_token())
    assert identity == GoogleIdentity(subject="1234567890", email="aziza@gmail.com")


@pytest.mark.parametrize(
    "token",
    [
        pytest.param(_token(key=_OTHER_KEY), id="forged-signature"),
        pytest.param(_token(aud="some-other-app"), id="other-audience"),
        pytest.param(_token(iss="https://evil.example"), id="other-issuer"),
        pytest.param(_token(exp=int(time.time()) - 3600), id="expired"),
        pytest.param(_token(email_verified=False), id="email-unverified"),
        pytest.param(_token(email=None), id="no-email"),
        pytest.param("not-a-jwt", id="garbage"),
    ],
)
async def test_verifier_rejects(token: str) -> None:
    with pytest.raises(InvalidGoogleToken):
        await _verifier().verify(token)


async def test_verifier_without_client_ids_is_disabled() -> None:
    with pytest.raises(GoogleSignInDisabled):
        await _verifier(client_ids=[]).verify(_token())


def test_client_ids_accept_a_comma_separated_list() -> None:
    settings = Settings(_env_file=None, GOOGLE_CLIENT_IDS="a.apps, b.apps ,")
    assert settings.GOOGLE_CLIENT_IDS == ["a.apps", "b.apps"]


# --- the endpoint --------------------------------------------------------------


class _FakeVerifier:
    """`"<sub>|<email>"` verifies as that identity; `"bad"` does not."""

    disabled = False

    async def verify(self, id_token: str) -> GoogleIdentity:
        if self.disabled:
            raise GoogleSignInDisabled
        if id_token == "bad":
            raise InvalidGoogleToken
        subject, email = id_token.split("|")
        return GoogleIdentity(subject=subject, email=email)


@pytest.fixture
async def session_factory() -> AsyncGenerator[async_sessionmaker[AsyncSession], None]:
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    factory = async_sessionmaker(bind=engine, expire_on_commit=False)
    try:
        yield factory
    finally:
        await engine.dispose()


@pytest.fixture
def verifier() -> _FakeVerifier:
    return _FakeVerifier()


@pytest.fixture
async def client(
    session_factory: async_sessionmaker[AsyncSession], verifier: _FakeVerifier
) -> AsyncGenerator[AsyncClient, None]:
    from app.core.config import get_settings
    from app.db.session import get_session

    async def _override_session() -> AsyncGenerator[AsyncSession, None]:
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = _override_session
    app.dependency_overrides[get_settings] = lambda: Settings(
        _env_file=None, JWT_SECRET=TEST_JWT_SECRET
    )
    app.dependency_overrides[auth_rate_limit] = lambda: None
    app.dependency_overrides[get_google_verifier] = lambda: verifier
    set_rate_limiter(RateLimiter(enabled=False))
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            yield ac
    finally:
        app.dependency_overrides.clear()
        set_rate_limiter(None)


async def _google(client: AsyncClient, token: str, device_id: str = "phone"):
    return await client.post(
        "/auth/google", json={"id_token": token, "device_id": device_id, "locale": "uz"}
    )


async def _users(factory: async_sessionmaker[AsyncSession]) -> list[User]:
    async with factory() as session:
        return list((await session.execute(select(User))).scalars())


async def test_first_google_sign_in_creates_a_verified_passwordless_account(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    response = await _google(client, "sub-1|aziza@gmail.com")
    assert response.status_code == 200, response.text
    tokens = response.json()

    me = await client.get("/auth/me", headers={"Authorization": f"Bearer {tokens['access_token']}"})
    assert me.json()["email"] == "aziza@gmail.com"
    assert me.json()["email_verified_at"] is not None

    [user] = await _users(session_factory)
    assert user.password_hash is None
    assert user.locale == "uz"


async def test_repeat_google_sign_in_reaches_the_same_account(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    await _google(client, "sub-1|aziza@gmail.com")
    # The Google address changed; the subject still identifies the account.
    response = await _google(client, "sub-1|aziza.new@gmail.com", device_id="tablet")
    assert response.status_code == 200
    assert len(await _users(session_factory)) == 1


async def test_google_links_an_account_whose_email_was_verified(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    await client.post(
        "/auth/register",
        json={"email": "aziza@gmail.com", "password": PASSWORD, "locale": "en"},
    )
    async with session_factory() as session:
        user = (await session.execute(select(User))).scalar_one()
        user.email_verified_at = user.created_at
        await session.commit()

    assert (await _google(client, "sub-1|aziza@gmail.com")).status_code == 200
    [user] = await _users(session_factory)
    assert user.password_hash is not None
    login = await client.post(
        "/auth/login", json={"email": "aziza@gmail.com", "password": PASSWORD}
    )
    assert login.status_code == 200


async def test_google_clears_the_password_of_an_unverified_account(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    # Someone registers the victim's address before the victim ever arrives.
    await client.post(
        "/auth/register",
        json={"email": "aziza@gmail.com", "password": PASSWORD, "locale": "en"},
    )
    squatter = await client.post(
        "/auth/login", json={"email": "aziza@gmail.com", "password": PASSWORD}
    )
    assert squatter.status_code == 200

    assert (await _google(client, "sub-1|aziza@gmail.com")).status_code == 200

    # The password set by whoever registered first no longer works ...
    login = await client.post(
        "/auth/login", json={"email": "aziza@gmail.com", "password": PASSWORD}
    )
    assert login.status_code == 401
    # ... and their session is gone.
    refresh = await client.post(
        "/auth/refresh", json={"refresh_token": squatter.json()["refresh_token"]}
    )
    assert refresh.status_code == 401
    [user] = await _users(session_factory)
    assert user.email_verified_at is not None


async def test_invalid_google_token_is_401(client: AsyncClient) -> None:
    assert (await _google(client, "bad")).status_code == 401


async def test_google_sign_in_unconfigured_is_503(
    client: AsyncClient, verifier: _FakeVerifier
) -> None:
    verifier.disabled = True
    assert (await _google(client, "sub-1|aziza@gmail.com")).status_code == 503


async def test_inactive_account_cannot_sign_in_with_google(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    await _google(client, "sub-1|aziza@gmail.com")
    async with session_factory() as session:
        user = (await session.execute(select(User))).scalar_one()
        user.is_active = False
        await session.commit()
    assert (await _google(client, "sub-1|aziza@gmail.com")).status_code == 401


# --- deletion ----------------------------------------------------------------


async def test_google_account_is_deleted_with_a_fresh_google_token(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    tokens = (await _google(client, "sub-1|aziza@gmail.com")).json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}

    wrong = await client.request(
        "DELETE", "/users/me", json={"google_id_token": "sub-2|other@gmail.com"}, headers=headers
    )
    assert wrong.status_code == 403

    ok = await client.request(
        "DELETE", "/users/me", json={"google_id_token": "sub-1|aziza@gmail.com"}, headers=headers
    )
    assert ok.status_code == 204
    async with session_factory() as session:
        assert (await session.execute(select(UserIdentity))).first() is None

    # The same Google account can start a new account afterwards.
    again = await _google(client, "sub-1|aziza@gmail.com")
    assert again.status_code == 200
    live = [u for u in await _users(session_factory) if u.deleted_at is None]
    assert len(live) == 1


async def test_delete_needs_exactly_one_proof(client: AsyncClient) -> None:
    tokens = (await _google(client, "sub-1|aziza@gmail.com")).json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    for body in ({}, {"password": PASSWORD, "google_id_token": "sub-1|aziza@gmail.com"}):
        response = await client.request("DELETE", "/users/me", json=body, headers=headers)
        assert response.status_code == 422
