"""Portable column types shared by feature models.

`JSONType`
    Plain JSON on SQLite (the test suite), JSONB on PostgreSQL -- the same
    variant every feature module used to declare privately.

`EncryptedText`
    Application-level AES-256-GCM column encryption for free text a user
    types into a private log (`docs/plan.md` section 11,
    `docs/privacy/data-map.md` "Server ustun shifrlash"). The database, its
    backups and anyone with SQL access see only ciphertext; the ORM hands the
    application plaintext.

Stored format
=============

``v<version>:<base64url-no-padding(nonce || ciphertext || tag)>``

* ``nonce``   -- 12 random bytes, fresh for every value, so the same note
  written twice never produces the same ciphertext.
* ``tag``     -- the 16-byte GCM authentication tag; any modified byte makes
  decryption fail loudly instead of returning garbage.
* ``v<version>`` -- the key version (`FIELD_ENC_KEY_VERSION`). It is also the
  GCM associated data, so relabelling a value with another version fails
  authentication too.

Key handling
============

* `FIELD_ENC_KEY` is the base64 (standard or URL-safe) encoding of exactly 32
  random bytes. Generate one with::

      python -c "import base64, os; print(base64.b64encode(os.urandom(32)).decode())"

* `ENV=dev` with the placeholder (or an empty) key uses `DEV_FIELD_ENC_KEY`:
  ``sha256(b"kunim-dev-only-field-enc-key")``. It is deterministic and public
  -- tests install the same key (`tests/conftest.py`) -- so it must never
  protect real data.
* Any other `ENV` with the placeholder or an empty key raises
  `FieldEncryptionConfigError`. `app.main.create_app` builds the cipher at
  startup, so a misconfigured production process refuses to start rather
  than storing notes in plaintext or under a public key.
* A key that is set but malformed (not base64, not 32 bytes) is an error in
  every environment.
* Only the current key version can be decrypted. Rotating the key is a
  re-encryption migration, never an in-place swap (see `app.core.config`).

Nothing here logs, and no exception message carries plaintext, ciphertext or
key material.

Because every write uses a fresh nonce, an `EncryptedText` column can never
be compared or searched in SQL (`WHERE note = ...` never matches).
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import os
from functools import cache
from typing import Any

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from sqlalchemy import JSON, Text
from sqlalchemy import inspect as sa_inspect
from sqlalchemy.dialects import postgresql
from sqlalchemy.exc import NoInspectionAvailable
from sqlalchemy.types import TypeDecorator

from app.core.config import Settings, get_settings

JSONType = JSON().with_variant(postgresql.JSONB(), "postgresql")

KEY_BYTES = 32
NONCE_BYTES = 12
TAG_BYTES = 16

DEV_FIELD_ENC_KEY = hashlib.sha256(b"kunim-dev-only-field-enc-key").digest()
"""Public, deterministic key for `ENV=dev` and the test suite only."""

_PLACEHOLDER_PREFIX = "change-me"


class FieldEncryptionError(Exception):
    """Base class; messages never include plaintext, ciphertext or keys."""


class FieldEncryptionConfigError(FieldEncryptionError):
    """`FIELD_ENC_KEY` / `FIELD_ENC_KEY_VERSION` are missing or malformed."""


class FieldDecryptionError(FieldEncryptionError):
    """A stored value is malformed, under an unknown key version, or tampered with."""


def _b64encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _b64decode(text: str) -> bytes:
    padded = text + "=" * (-len(text) % 4)
    return base64.b64decode(padded.encode("ascii"), altchars=b"-_", validate=True)


class FieldCipher:
    """AES-256-GCM with one current key version."""

    __slots__ = ("_aead", "_prefix", "_version")

    def __init__(self, key: bytes, *, version: int = 1) -> None:
        if len(key) != KEY_BYTES:
            raise FieldEncryptionConfigError("field encryption key must be exactly 32 bytes")
        if version < 1:
            raise FieldEncryptionConfigError("field encryption key version must be >= 1")
        self._aead = AESGCM(key)
        self._version = version
        self._prefix = f"v{version}"

    @property
    def version(self) -> int:
        return self._version

    def __repr__(self) -> str:  # never expose key material
        return f"<FieldCipher version={self._version}>"

    def encrypt(self, plaintext: str) -> str:
        nonce = os.urandom(NONCE_BYTES)
        sealed = self._aead.encrypt(nonce, plaintext.encode("utf-8"), self._prefix.encode("ascii"))
        return f"{self._prefix}:{_b64encode(nonce + sealed)}"

    def decrypt(self, token: str) -> str:
        prefix, separator, body = token.partition(":")
        if not separator or prefix != self._prefix:
            raise FieldDecryptionError("encrypted value has an unknown format or key version")
        try:
            blob = _b64decode(body)
        except (binascii.Error, ValueError, UnicodeEncodeError):
            raise FieldDecryptionError("encrypted value is not valid base64url") from None
        if len(blob) < NONCE_BYTES + TAG_BYTES:
            raise FieldDecryptionError("encrypted value is truncated")
        try:
            plaintext = self._aead.decrypt(
                blob[:NONCE_BYTES], blob[NONCE_BYTES:], prefix.encode("ascii")
            )
        except InvalidTag:
            raise FieldDecryptionError("encrypted value failed authentication") from None
        return plaintext.decode("utf-8")


def is_placeholder_key(raw: str) -> bool:
    value = raw.strip()
    return not value or value.startswith(_PLACEHOLDER_PREFIX)


def decode_key(raw: str) -> bytes:
    """Decode a base64 / base64url `FIELD_ENC_KEY` into exactly 32 bytes."""
    try:
        key = _b64decode(raw.strip().replace("+", "-").replace("/", "_"))
    except (binascii.Error, ValueError, UnicodeEncodeError):
        raise FieldEncryptionConfigError(
            "FIELD_ENC_KEY must be the base64 encoding of 32 random bytes"
        ) from None
    if len(key) != KEY_BYTES:
        raise FieldEncryptionConfigError(
            "FIELD_ENC_KEY must be the base64 encoding of 32 random bytes"
        )
    return key


def build_field_cipher(settings: Settings) -> FieldCipher:
    """Build the cipher for `settings`, refusing a placeholder key outside dev."""
    if is_placeholder_key(settings.FIELD_ENC_KEY):
        if settings.ENV == "dev":
            return FieldCipher(DEV_FIELD_ENC_KEY, version=settings.FIELD_ENC_KEY_VERSION)
        raise FieldEncryptionConfigError(
            f"FIELD_ENC_KEY is not set (placeholder or empty) with ENV={settings.ENV}; "
            "refusing to start rather than store private notes unencrypted"
        )
    return FieldCipher(decode_key(settings.FIELD_ENC_KEY), version=settings.FIELD_ENC_KEY_VERSION)


_cipher: FieldCipher | None = None


def get_field_cipher() -> FieldCipher:
    """The process-wide cipher, built from `get_settings()` on first use."""
    global _cipher
    if _cipher is None:
        _cipher = build_field_cipher(get_settings())
    return _cipher


def set_field_cipher(cipher: FieldCipher | None) -> None:
    """Install a cipher (tests); `None` rebuilds from settings on next use."""
    global _cipher
    _cipher = cipher


class EncryptedText(TypeDecorator[str]):
    """`TEXT` column holding AES-256-GCM ciphertext; plaintext `str` in Python."""

    impl = Text
    cache_ok = True

    def process_bind_param(self, value: Any, dialect: Any) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str):
            raise TypeError("EncryptedText accepts str values only")
        return get_field_cipher().encrypt(value)

    def process_result_value(self, value: Any, dialect: Any) -> str | None:
        if value is None:
            return None
        return get_field_cipher().decrypt(value)


@cache
def encrypted_column_names(model: type[Any]) -> frozenset[str]:
    """Attribute names of every `EncryptedText` column on an ORM model.

    A class that is not a mapped model has none.
    """
    try:
        columns = sa_inspect(model).columns
    except NoInspectionAvailable:
        return frozenset()
    return frozenset(column.key for column in columns if isinstance(column.type, EncryptedText))


def seal_encrypted_fields(model: type[Any], row: dict[str, Any] | None) -> dict[str, Any] | None:
    """Encrypt a model's `EncryptedText` fields inside a plain dict snapshot.

    For JSON copies of a row stored elsewhere (`row_history.before/after`):
    ADR-0002 section 4 requires those columns to stay encrypted there too.
    """
    if row is None:
        return None
    names = encrypted_column_names(model)
    if not names:
        return row
    cipher = get_field_cipher()
    sealed = dict(row)
    for name in names:
        value = sealed.get(name)
        if isinstance(value, str):
            sealed[name] = cipher.encrypt(value)
    return sealed


def open_encrypted_fields(model: type[Any], row: dict[str, Any] | None) -> dict[str, Any] | None:
    """Inverse of `seal_encrypted_fields` for a dict snapshot.

    A value that is not valid ciphertext under the current key -- tampered, or
    never sealed -- raises `FieldDecryptionError`; it is never passed through.
    """
    if row is None:
        return None
    names = encrypted_column_names(model)
    if not names:
        return row
    cipher = get_field_cipher()
    opened = dict(row)
    for name in names:
        value = opened.get(name)
        if isinstance(value, str):
            opened[name] = cipher.decrypt(value)
    return opened
