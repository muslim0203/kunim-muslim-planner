"""`app.db.types.EncryptedText`: AES-256-GCM column encryption for private notes.

Unit level: the cipher round-trips, uses a fresh nonce per value, detects
tampering and relabelling, never leaks plaintext or key material in errors,
and refuses a placeholder key outside `ENV=dev`.

End to end: a note pushed over `/sync` is ciphertext in the table and in
`row_history` (ADR-0002 section 4), and plaintext again when pulled.
"""

from __future__ import annotations

import base64
import json
import os
import uuid
from collections.abc import Generator

import pytest
from pydantic import ValidationError
from sqlalchemy import select, text

from app.core.config import Settings
from app.db.types import (
    DEV_FIELD_ENC_KEY,
    NONCE_BYTES,
    TAG_BYTES,
    EncryptedText,
    FieldCipher,
    FieldDecryptionError,
    FieldEncryptionConfigError,
    build_field_cipher,
    decode_key,
    get_field_cipher,
    seal_encrypted_fields,
    set_field_cipher,
)
from app.modules.mood.models import MoodLog
from app.modules.sync.models import RowHistory
from tests import test_sync_harness as harness
from tests.test_wellbeing_sync import BUILDERS

client = harness.client
session_factory = harness.session_factory
two_clients = harness.two_clients

PLACEHOLDER = "change-me-in-production-32-bytes!"
URLSAFE_ALPHABET = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")


@pytest.fixture
def restore_dev_cipher() -> Generator[None, None, None]:
    yield
    set_field_cipher(FieldCipher(DEV_FIELD_ENC_KEY))


def _settings(**overrides: object) -> Settings:
    return Settings(_env_file=None, **overrides)


def _flip(token: str, index: int) -> str:
    prefix, body = token.split(":", 1)
    blob = bytearray(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
    blob[index] ^= 0x01
    return f"{prefix}:{base64.urlsafe_b64encode(bytes(blob)).rstrip(b'=').decode()}"


# --- the cipher ---------------------------------------------------------------------


@pytest.mark.parametrize(
    "plaintext", ["", "a", "Alhamdulillah — ҳамд, қувонч 🌙", "x" * 2000, "line\nbreak"]
)
def test_encrypt_then_decrypt_round_trips(plaintext: str) -> None:
    cipher = FieldCipher(os.urandom(32))
    assert cipher.decrypt(cipher.encrypt(plaintext)) == plaintext


def test_stored_format_is_version_prefix_and_unpadded_base64url() -> None:
    cipher = FieldCipher(os.urandom(32), version=3)
    token = cipher.encrypt("note")
    prefix, body = token.split(":", 1)
    assert prefix == "v3"
    assert set(body) <= URLSAFE_ALPHABET
    blob = base64.urlsafe_b64decode(body + "=" * (-len(body) % 4))
    assert len(blob) == NONCE_BYTES + len(b"note") + TAG_BYTES


def test_same_plaintext_encrypts_differently_every_time() -> None:
    cipher = FieldCipher(os.urandom(32))
    tokens = [cipher.encrypt("same note") for _ in range(50)]
    assert len(set(tokens)) == len(tokens)
    nonces = {base64.urlsafe_b64decode(t.split(":", 1)[1] + "==")[:NONCE_BYTES] for t in tokens}
    assert len(nonces) == len(tokens)


@pytest.mark.parametrize("index", [0, NONCE_BYTES, NONCE_BYTES + 2, -1])
def test_any_modified_byte_fails_authentication(index: int) -> None:
    """Nonce, ciphertext and tag are all covered."""
    cipher = FieldCipher(os.urandom(32))
    token = cipher.encrypt("private")
    with pytest.raises(FieldDecryptionError):
        cipher.decrypt(_flip(token, index))


def test_relabelling_the_key_version_fails() -> None:
    key = os.urandom(32)
    token = FieldCipher(key, version=1).encrypt("private")
    relabelled = "v2:" + token.split(":", 1)[1]
    with pytest.raises(FieldDecryptionError):  # the version is the GCM associated data
        FieldCipher(key, version=2).decrypt(relabelled)
    with pytest.raises(FieldDecryptionError):  # and an unknown version is refused outright
        FieldCipher(key, version=1).decrypt(relabelled)


def test_a_different_key_cannot_decrypt() -> None:
    token = FieldCipher(os.urandom(32)).encrypt("private")
    with pytest.raises(FieldDecryptionError):
        FieldCipher(os.urandom(32)).decrypt(token)


@pytest.mark.parametrize(
    "stored",
    ["plaintext note", "v1:", "v1:!!!not-base64!!!", "v1:" + "A" * 10, "v1", ":abc"],
)
def test_malformed_stored_values_are_refused_not_passed_through(stored: str) -> None:
    with pytest.raises(FieldDecryptionError):
        FieldCipher(os.urandom(32)).decrypt(stored)


def test_errors_and_repr_never_carry_plaintext_or_key_material() -> None:
    key = os.urandom(32)
    cipher = FieldCipher(key)
    token = cipher.encrypt("my secret note")
    with pytest.raises(FieldDecryptionError) as excinfo:
        cipher.decrypt(_flip(token, -1))
    message = str(excinfo.value) + repr(excinfo.value)
    for leaked in ("my secret note", token, base64.b64encode(key).decode(), key.hex()):
        assert leaked not in message
    assert base64.b64encode(key).decode() not in repr(cipher)
    assert key.hex() not in repr(cipher)


@pytest.mark.parametrize("length", [0, 16, 31, 33, 64])
def test_cipher_requires_a_32_byte_key(length: int) -> None:
    with pytest.raises(FieldEncryptionConfigError):
        FieldCipher(b"k" * length)


# --- the column type ----------------------------------------------------------------


def test_type_decorator_passes_none_through() -> None:
    column_type = EncryptedText()
    assert column_type.process_bind_param(None, None) is None
    assert column_type.process_result_value(None, None) is None


def test_type_decorator_encrypts_on_bind_and_decrypts_on_read() -> None:
    column_type = EncryptedText()
    stored = column_type.process_bind_param("hello", None)
    assert stored != "hello"
    assert stored.startswith("v1:")
    assert column_type.process_result_value(stored, None) == "hello"


def test_type_decorator_refuses_non_string_values() -> None:
    with pytest.raises(TypeError):
        EncryptedText().process_bind_param(42, None)


def test_seal_encrypted_fields_encrypts_only_encrypted_columns() -> None:
    row = {"note": "secret", "score": 3, "tags": ["calm"]}
    sealed = seal_encrypted_fields(MoodLog, row)
    assert sealed["note"].startswith("v1:")
    assert get_field_cipher().decrypt(sealed["note"]) == "secret"
    assert (sealed["score"], sealed["tags"]) == (3, ["calm"])
    assert row["note"] == "secret"  # the input is not mutated
    assert seal_encrypted_fields(MoodLog, None) is None
    assert seal_encrypted_fields(MoodLog, {"note": None}) == {"note": None}


# --- key configuration --------------------------------------------------------------


@pytest.mark.parametrize("key", [PLACEHOLDER, "", "   ", "change-me-in-production"])
def test_dev_with_a_placeholder_key_uses_the_public_dev_key(key: str) -> None:
    cipher = build_field_cipher(_settings(ENV="dev", FIELD_ENC_KEY=key))
    assert FieldCipher(DEV_FIELD_ENC_KEY).decrypt(cipher.encrypt("x")) == "x"


@pytest.mark.parametrize("env", ["staging", "prod"])
@pytest.mark.parametrize("key", [PLACEHOLDER, "", "change-me-in-production"])
def test_non_dev_with_a_placeholder_key_refuses(env: str, key: str) -> None:
    with pytest.raises(FieldEncryptionConfigError):
        build_field_cipher(_settings(ENV=env, FIELD_ENC_KEY=key))


@pytest.mark.parametrize("env", ["dev", "staging", "prod"])
@pytest.mark.parametrize(
    "key",
    [
        "not base64 at all!",
        base64.b64encode(os.urandom(31)).decode(),
        base64.b64encode(os.urandom(33)).decode(),
        "a" * 32,  # 32 ASCII characters is not 32 key bytes
    ],
)
def test_a_malformed_key_is_refused_in_every_env(env: str, key: str) -> None:
    with pytest.raises(FieldEncryptionConfigError):
        build_field_cipher(_settings(ENV=env, FIELD_ENC_KEY=key))


def test_standard_urlsafe_and_unpadded_base64_keys_all_decode() -> None:
    raw = bytes([0xFB, 0xFF, 0xBF]) + os.urandom(29)  # forces '+', '/' / '-', '_'
    for encoded in (
        base64.b64encode(raw).decode(),
        base64.urlsafe_b64encode(raw).decode(),
        base64.urlsafe_b64encode(raw).decode().rstrip("="),
    ):
        assert decode_key(encoded) == raw


def test_a_real_key_works_in_production_and_stamps_its_version() -> None:
    key = os.urandom(32)
    settings = _settings(
        ENV="prod", FIELD_ENC_KEY=base64.b64encode(key).decode(), FIELD_ENC_KEY_VERSION=2
    )
    token = build_field_cipher(settings).encrypt("x")
    assert token.startswith("v2:")
    assert FieldCipher(key, version=2).decrypt(token) == "x"


def test_key_version_must_be_positive() -> None:
    with pytest.raises(ValidationError):
        _settings(FIELD_ENC_KEY_VERSION=0)


def test_create_app_refuses_to_start_in_production_with_a_placeholder_key(
    monkeypatch, restore_dev_cipher
) -> None:
    from app import main

    # A real JWT_SECRET, so the field-key guard is the one that fires.
    prod = _settings(ENV="prod", FIELD_ENC_KEY=PLACEHOLDER, JWT_SECRET="j" * 48)
    monkeypatch.setattr(main, "get_settings", lambda: prod)
    monkeypatch.setattr("app.db.types.get_settings", lambda: prod)
    set_field_cipher(None)
    with pytest.raises(FieldEncryptionConfigError):
        main.create_app()


# --- end to end: encrypted at rest, plaintext over the wire --------------------------


@pytest.mark.parametrize("entity_name", sorted(BUILDERS))
async def test_note_is_ciphertext_at_rest_and_plaintext_when_pulled(
    two_clients, session_factory, entity_name: str
) -> None:
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    payload = BUILDERS[entity_name](row_id)
    note = payload["note"]
    alice.stage(entity_name, payload)
    assert (await alice.push()).json()["results"][0]["status"] == "applied"

    async with session_factory() as session:
        raw = (await session.execute(text(f"SELECT note FROM {entity_name}"))).scalar_one()
        assert raw.startswith("v1:")
        assert note not in raw
        assert FieldCipher(DEV_FIELD_ENC_KEY).decrypt(raw) == note

        # ADR-0002 section 4: `row_history` snapshots keep the column encrypted.
        raw_history = (await session.execute(text("SELECT after FROM row_history"))).scalars().all()
        assert raw_history
        for snapshot in raw_history:
            serialised = snapshot if isinstance(snapshot, str) else json.dumps(snapshot)
            assert note not in serialised
        history = (
            (await session.execute(select(RowHistory).where(RowHistory.entity == entity_name)))
            .scalars()
            .all()
        )
        assert [get_field_cipher().decrypt(entry.after["note"]) for entry in history] == [note]

    await bob.pull_all()
    assert bob.rows[(entity_name, row_id)]["note"] == note


async def test_a_null_note_stays_null_at_rest(two_clients, session_factory) -> None:
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    payload = BUILDERS["mood_logs"](row_id) | {"note": None}
    alice.stage("mood_logs", payload)
    assert (await alice.push()).json()["results"][0]["status"] == "applied"

    async with session_factory() as session:
        assert (await session.execute(text("SELECT note FROM mood_logs"))).scalar_one() is None

    await bob.pull_all()
    assert bob.rows[("mood_logs", row_id)]["note"] is None
