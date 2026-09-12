"""Business logic for `/preferences`: lazy creation, deep-merge PATCH.

`server_version` bump rule
--------------------------
`docs/adr/0002-sync.md` ("Required columns" / "Rejada aniqlanmagan" table)
mandates a per-user **monotonic** counter, produced by a row-locked
`UPDATE ... RETURNING` against a dedicated `sync_user_state` table, and it
explicitly forbids a global `BIGSERIAL` (commit order can differ from the
order a sequence hands out numbers, which would let a pull cursor skip a
row). That `sync_user_state` counter is Phase 2 `app/modules/sync/`
infrastructure and does not exist yet, and this module does not own (and will
not create) it.

`preferences` has exactly one row per user, so for *this table only* the
smallest correct substitute is to make the row's own `server_version` do
double duty as the per-user counter: `repository.update()` bumps it with a
single atomic `UPDATE preferences SET server_version = server_version + 1 ...`
statement. Because there is only ever one row per user, "this row's counter"
and "this user's counter" are the same number -- there is no second row that
could race it or fragment the sequence. This is **not** a general mechanism:
it must not be copied onto any multi-row synced table without the real
`sync_user_state` counter, and Phase 2's sync module should replace it here
too once that counter exists, for a single code path.
"""

from __future__ import annotations

from typing import Any

from fastapi import HTTPException, status
from pydantic import ValidationError

from app.modules.preferences.models import Preferences
from app.modules.preferences.repository import PreferencesRepository
from app.modules.preferences.schemas import (
    Notifications,
    PrayerSettings,
    PreferencesUpdate,
    PrivacyConsents,
    UISettings,
)
from app.modules.users.models import User

# Every top-level JSONB key, and the schema its merged value must validate
# against. Order doesn't matter; this is also the authoritative key list.
_SUB_SCHEMAS: dict[str, type] = {
    "prayer_settings": PrayerSettings,
    "notifications": Notifications,
    "privacy_consents": PrivacyConsents,
    "ui": UISettings,
}


def _default_document() -> dict[str, Any]:
    return {key: schema().model_dump(mode="json") for key, schema in _SUB_SCHEMAS.items()}


def _deep_merge(base: dict[str, Any], patch: dict[str, Any]) -> dict[str, Any]:
    """Recursively merge `patch` into `base`.

    A key present in `patch` whose value is itself a dict is merged
    key-by-key rather than replacing `base[key]` wholesale -- this is what
    keeps a PATCH of e.g. `prayer_settings.adjustments.fajr` from wiping the
    other four adjustment fields, at every nesting level.
    """
    merged = dict(base)
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


class PreferencesService:
    def __init__(self, repo: PreferencesRepository) -> None:
        self._repo = repo

    async def get_or_create(self, user: User) -> Preferences:
        prefs = await self._repo.get_by_user_id(user.id)
        if prefs is not None:
            return prefs
        return await self._repo.create(user_id=user.id, document=_default_document())

    async def update(self, user: User, payload: PreferencesUpdate) -> Preferences:
        prefs = await self.get_or_create(user)
        patch = payload.model_dump(exclude_unset=True)

        next_document: dict[str, Any] = {}
        for key, schema in _SUB_SCHEMAS.items():
            current = getattr(prefs, key)
            sub_patch = patch.get(key)
            if sub_patch is None:
                # Not present in this PATCH at all: leave the stored value
                # byte-for-byte as it is.
                next_document[key] = current
                continue

            merged = _deep_merge(current, sub_patch)
            try:
                # Re-validate the *whole* merged sub-object, not just the
                # patched keys: this both rejects an invalid value anywhere
                # in it and guarantees untouched keys keep their exact prior
                # value (they were never removed, only merged over).
                validated = schema.model_validate(merged)
            except ValidationError as exc:
                first_error = exc.errors()[0]
                field = ".".join(str(part) for part in first_error["loc"])
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"Invalid {key}.{field}: {first_error['msg']}",
                ) from exc
            next_document[key] = validated.model_dump(mode="json")

        return await self._repo.update(prefs, document=next_document)
