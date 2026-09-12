"""Pydantic schemas for `/preferences`.

Every sub-object is typed and carries sane defaults, so a freshly created row
(`service.get_or_create`) is always well-formed and `GET /preferences` never
needs a null-check on the client.

`PreferencesUpdate` deliberately accepts a loosely-typed partial `dict` per
top-level key rather than a partial version of each typed schema below.
`service.py` deep-merges each dict into the *stored* dict and then
re-validates the merged result against the strict schema here -- that is what
makes "PATCH one nested key without wiping its siblings" work at every
nesting level (top-level key, and inside `prayer_settings.adjustments` /
`notifications.quiet_hours`), and it also means an invalid value anywhere in
the merged object is rejected before it is written.
"""

from __future__ import annotations

import re
import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, Field, field_validator


def _validate_iana_timezone(value: str | None) -> str | None:
    if value is None:
        return value
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError, KeyError) as exc:
        raise ValueError(f"Unknown IANA timezone: {value!r}") from exc
    return value


_HHMM_RE = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


def _validate_hh_mm(value: str) -> str:
    if not _HHMM_RE.match(value):
        raise ValueError(f"Expected a 24-hour 'HH:MM' time, got {value!r}")
    return value


class PrayerCalculationMethod(StrEnum):
    """Allowed `prayer_settings.method` values.

    Names the calculation-method set the mobile app's `adhan_dart` library
    exposes (`docs/plan.md` section 6: MWL, Egyptian, Karachi, Umm al-Qura,
    Dubai, Kuwait, Qatar, Singapore, Turkey, Tehran, Moonsighting), plus the
    "Uzbekistan (Muftiyat)" preset the plan calls out by name. There is no
    Python `adhan` package here -- prayer-time *calculation* is a mobile-side,
    client-clock concern (see plan section 6: "app start + har kuni 00:05...
    `zonedSchedule`"); this backend only stores the user's chosen method, so
    this enum's string values are this module's own naming, not imported from
    a library.
    """

    muslim_world_league = "muslim_world_league"  # MWL
    egyptian = "egyptian"
    karachi = "karachi"
    umm_al_qura = "umm_al_qura"
    dubai = "dubai"
    kuwait = "kuwait"
    qatar = "qatar"
    singapore = "singapore"
    turkey = "turkey"
    tehran = "tehran"
    moonsighting = "moonsighting"
    uzbekistan_muftiyat = "uzbekistan_muftiyat"


class Madhab(StrEnum):
    hanafi = "hanafi"
    shafi = "shafi"


class HighLatitudeRule(StrEnum):
    """adhan's three standard high-latitude adjustment rules."""

    middle_of_the_night = "middle_of_the_night"
    seventh_of_the_night = "seventh_of_the_night"
    twilight_angle = "twilight_angle"


class PrayerAdjustments(BaseModel):
    """Per-prayer minute offsets applied on top of the calculation method."""

    model_config = ConfigDict(extra="forbid")

    fajr: int = 0
    dhuhr: int = 0
    asr: int = 0
    maghrib: int = 0
    isha: int = 0


class PrayerLocation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lat: float | None = None
    lon: float | None = None
    city: str | None = None
    timezone: str | None = None

    @field_validator("timezone")
    @classmethod
    def _check_timezone(cls, v: str | None) -> str | None:
        return _validate_iana_timezone(v)


class PrayerSettings(BaseModel):
    model_config = ConfigDict(extra="forbid")

    method: PrayerCalculationMethod = PrayerCalculationMethod.muslim_world_league
    madhab: Madhab = Madhab.shafi
    high_latitude_rule: HighLatitudeRule = HighLatitudeRule.middle_of_the_night
    adjustments: PrayerAdjustments = Field(default_factory=PrayerAdjustments)
    location: PrayerLocation = Field(default_factory=PrayerLocation)


class QuietHours(BaseModel):
    model_config = ConfigDict(extra="forbid")

    enabled: bool = False
    start: str = "22:00"
    end: str = "06:00"

    @field_validator("start", "end")
    @classmethod
    def _check_hh_mm(cls, v: str) -> str:
        return _validate_hh_mm(v)


class Notifications(BaseModel):
    """Per-category toggles (`docs/plan.md` section 10) plus quiet hours."""

    model_config = ConfigDict(extra="forbid")

    prayer: bool = True
    habits: bool = True
    tasks: bool = True
    quran: bool = True
    wellbeing: bool = True
    ai_recommendations: bool = True
    reviews: bool = True
    system: bool = True
    quiet_hours: QuietHours = Field(default_factory=QuietHours)


class PrivacyConsents(BaseModel):
    """Three independent consents (`docs/plan.md` section 11).

    Deliberately three separate booleans, never one combined flag: a user may
    accept analytics while declining AI personalization, or accept DW cloud
    stats while declining both of the others.
    """

    model_config = ConfigDict(extra="forbid")

    analytics: bool = False
    ai_personalization: bool = False
    dw_cloud_stats: bool = False


class Theme(StrEnum):
    light = "light"
    dark = "dark"
    system = "system"


class UISettings(BaseModel):
    model_config = ConfigDict(extra="forbid")

    theme: Theme = Theme.system
    # 0 = Sunday .. 6 = Saturday (plan/ADR are silent on the convention; this
    # module's own choice -- see report to next agent). Default: Monday.
    first_day_of_week: int = Field(default=1, ge=0, le=6)


class PreferencesOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    prayer_settings: PrayerSettings
    notifications: Notifications
    privacy_consents: PrivacyConsents
    ui: UISettings
    server_version: int
    created_at: datetime
    updated_at: datetime


class PreferencesUpdate(BaseModel):
    """Partial update: each present top-level key is deep-merged into the
    stored sub-object (see module docstring and `service.py`)."""

    model_config = ConfigDict(extra="forbid")

    prayer_settings: dict[str, Any] | None = None
    notifications: dict[str, Any] | None = None
    privacy_consents: dict[str, Any] | None = None
    ui: dict[str, Any] | None = None
