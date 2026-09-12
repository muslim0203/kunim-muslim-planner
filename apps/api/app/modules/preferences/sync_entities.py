"""Registers `preferences` as a syncable entity (ADR-0002 rule 19).

This file is the whole of what a feature module has to add to become
syncable -- `app.modules.sync.registry.discover()` finds it by name, so
nothing inside `app/modules/sync/` mentions preferences. Phase-2 entities
(tasks, habits, goals, calendar) follow exactly this shape; see the
`app.modules.sync.registry` module docstring for the full contract.

Merge level: whole-row LWW, no field merge (ADR rule 19). Natural key is
`(user_id)` -- one row per user -- which is also what makes ADR rule 14 apply
here: if two offline devices each mint a preferences row for the same user,
the older `created_at` survives and the other id becomes a `merged_into`
tombstone.
"""

from __future__ import annotations

from app.modules.preferences.models import Preferences
from app.modules.preferences.schemas import (
    Notifications,
    PrayerSettings,
    PrivacyConsents,
    UISettings,
)
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import SyncEntity, register_entity
from app.modules.sync.schemas import SyncRowBase


class PreferencesSyncRow(SyncRowBase):
    """Wire shape of a `preferences` row: the seven sync columns + the document.

    Every field name matches a column on `Preferences`, which is what lets the
    generic repository persist it with `setattr`. The typed sub-objects are
    reused from the REST schemas, so a pushed row is validated exactly as
    strictly as a `PATCH /preferences` body -- an invalid one is
    `rejected`/`schema_invalid` rather than silently stored.
    """

    prayer_settings: PrayerSettings
    notifications: Notifications
    privacy_consents: PrivacyConsents
    ui: UISettings


register_entity(
    SyncEntity(
        name="preferences",
        model=Preferences,
        schema=PreferencesSyncRow,
        policy=ADR_ENTITY_POLICIES["preferences"],
    )
)
