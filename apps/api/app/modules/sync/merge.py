"""The ADR-0002 conflict matrix, expressed as data.

`docs/adr/0002-sync.md` says merge lives **only on the server** ("Merge faqat
serverda"), and that every rule must carry its matrix row number and have a
matching test. This module is the whole of it: rows 1-7 and 23-24 are the
generic engine below; rows 8-22 and 25 (`family_logs`, appended after the
original 24) are per-entity `MergePolicy` data, either declared by the
feature module or taken from `ADR_ENTITY_POLICIES` here.

Everything in this module is a pure function over dictionaries. It touches no
session, no ORM and no HTTP, which is what lets
`tests/test_sync_merge_matrix.py` address one matrix row at a time.

Dict convention
---------------
Rows are `schema.model_dump()` output: timestamps are aware UTC `datetime`s
(via `schemas.UtcDatetime`), ids are `uuid.UUID`, nested values are plain
JSON-ish structures. `service.py` is responsible for producing that shape.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any

from app.modules.sync.registry import (
    FieldRule,
    MergePolicy,
    MergeStrategy,
    SyncDirection,
    SyncEntity,
)
from app.modules.sync.schemas import (
    FUTURE_TOLERANCE_HOURS,
    SLUG_LIST_MAX_ITEMS,
    ChangeStatus,
    RejectReason,
    SyncOp,
)

# Fields that never take part in deciding `applied` vs `conflict`:
#   * `created_at` -- ADR rule 7 normalises it silently and still answers
#     `applied`, and §1 says merge does not use it;
#   * `server_version` -- server-owned, the client's copy is always stale.
_STATUS_EXEMPT_FIELDS = frozenset({"created_at", "server_version"})


@dataclass(frozen=True, slots=True)
class MergeOutcome:
    status: ChangeStatus
    row: dict[str, Any] | None
    reason: RejectReason | None = None

    @property
    def rejected(self) -> bool:
        return self.status is ChangeStatus.rejected


def _rejected(reason: RejectReason) -> MergeOutcome:
    return MergeOutcome(status=ChangeStatus.rejected, row=None, reason=reason)


# --- matrix rows 23 & 24: the change never reaches a row --------------------


def precheck(
    *,
    entity: SyncEntity | None,
    payload_user_id: Any,
    jwt_user_id: Any,
) -> RejectReason | None:
    """Entity-level admission check.

    Rule 23: unknown entity, or a payload claiming another user's `user_id`.
    Rule 24: a push at a pull-only entity (`content`, Qur'an text, presets).
    """
    if entity is None:
        return RejectReason.unknown_entity  # ADR rule 23
    if entity.direction is SyncDirection.pull_only:
        return RejectReason.readonly_entity  # ADR rule 24
    if payload_user_id is not None and payload_user_id != jwt_user_id:
        return RejectReason.foreign_user  # ADR rule 23 / §1 `user_id`
    return None


# --- field combinators ------------------------------------------------------


def _max_wins(left: Any, right: Any) -> Any:
    """Larger value wins; `None` is the smallest (ADR rules 8, 9, 13, 16, 21)."""
    if left is None:
        return right
    if right is None:
        return left
    return left if left >= right else right


def _enum_max_wins(left: Any, right: Any, order: tuple[str, ...]) -> Any:
    """`max_wins` over an explicit ordering (ADR rule 10: none < qaza < alone < jamaah)."""
    if left is None:
        return right
    if right is None:
        return left
    ranks = {value: index for index, value in enumerate(order)}
    # An unknown value ranks below every known one rather than raising: a
    # newer client must never be able to crash an older server's merge.
    return left if ranks.get(str(left), -1) >= ranks.get(str(right), -1) else right


def _set_key(value: Any) -> tuple[str, str]:
    """Identity of a set member: equal type name and text are one item."""
    return (type(value).__name__, str(value))


def _as_values(source: Any) -> list[Any]:
    if isinstance(source, (list, tuple, set, frozenset)):
        return list(source)
    return [] if source is None else [source]


def _set_union(winner: Any, loser: Any, *, max_items: int | None = None) -> list[Any]:
    """Union of two collections treated as sets (ADR rules 11 and 25).

    Within `max_items` (or with no cap) the union is sorted by
    `(type name, str(value))`, so both devices converge on byte-identical
    output regardless of which one pushed first.

    Over `max_items` the choice of survivors is deterministic: the LWW
    winner's distinct items first, in the winner's own list order; then the
    loser's remaining items in that same sorted order; then the first
    `max_items` of that sequence are kept. A wire-valid winner never exceeds
    the cap, so it always survives whole and the merged row always
    re-validates against the schema's list limit.

    The survivors are returned sorted, exactly like an uncapped union. Any
    other output order would not be a fixed point: merging the stored list
    with an unchanged copy of itself stays within the cap, comes back sorted,
    and would turn a no-op re-push into a `conflict`.
    """
    unique: dict[tuple[str, str], Any] = {}
    for value in (*_as_values(winner), *_as_values(loser)):
        unique.setdefault(_set_key(value), value)
    ordered = [unique[key] for key in sorted(unique)]
    if max_items is None or len(ordered) <= max_items:
        return ordered

    kept: dict[tuple[str, str], Any] = {}
    for value in _as_values(winner):
        kept.setdefault(_set_key(value), value)
    for value in ordered:  # only the loser's remaining items are still new here
        kept.setdefault(_set_key(value), value)
    survivors = list(kept.values())[:max_items]
    return sorted(survivors, key=_set_key)


def _apply_field_rule(
    rule: FieldRule,
    *,
    merged: dict[str, Any],
    winner: dict[str, Any],
    incoming: dict[str, Any],
    existing: dict[str, Any],
) -> None:
    left = incoming.get(rule.field)
    right = existing.get(rule.field)

    if rule.strategy is MergeStrategy.lww:
        merged[rule.field] = winner.get(rule.field)
    elif rule.strategy is MergeStrategy.max_wins:
        merged[rule.field] = _max_wins(left, right)
    elif rule.strategy is MergeStrategy.enum_max_wins:
        merged[rule.field] = _enum_max_wins(left, right, rule.enum_order)
    elif rule.strategy is MergeStrategy.set_union:
        loser = existing if winner is incoming else incoming
        merged[rule.field] = _set_union(
            winner.get(rule.field), loser.get(rule.field), max_items=rule.max_items
        )
    elif rule.strategy in (MergeStrategy.grouped_lww, MergeStrategy.derived):
        # Rule 12: the whole group comes from one winner, and a derived field
        # follows its group instead of being max-wins in its own right.
        merged[rule.field] = winner.get(rule.field)
    else:  # pragma: no cover - StrEnum is exhaustive
        raise ValueError(f"unhandled merge strategy {rule.strategy!r}")


# --- the engine -------------------------------------------------------------


def _normalise_created_at(row: dict[str, Any]) -> dict[str, Any]:
    """ADR rule 7: `created_at > updated_at` is normalised, never rejected."""
    created_at = row.get("created_at")
    updated_at = row.get("updated_at")
    if created_at is not None and updated_at is not None and created_at > updated_at:
        row = {**row, "created_at": updated_at}
    return row


def _comparable(row: dict[str, Any], policy: MergePolicy) -> dict[str, Any]:
    skip = _STATUS_EXEMPT_FIELDS | set(policy.ignored_fields)
    return {key: value for key, value in row.items() if key not in skip}


def _resolve_deletion(
    merged: dict[str, Any], incoming: dict[str, Any], existing: dict[str, Any]
) -> dict[str, Any]:
    """ADR rule 5: soft delete beats last-write-wins, resurrection needs a later upsert.

    Interpretation (the ADR phrases this as "`deleted_at > updated_at` -> the
    delete wins"): `updated_at` there is the timestamp of a *live* edit, not
    the delete's own `updated_at` -- a delete normally carries
    `deleted_at == updated_at`, so a literal reading would make every delete
    lose against itself. So the delete survives unless some side is still
    alive with a strictly later `updated_at`, which is exactly the ADR's
    "resurrection only via a later upsert with `updated_at > deleted_at`".
    Ties therefore keep the row deleted; that direction is recoverable (the
    row is still there, `row_history` holds it), whereas a wrong resurrection
    is the bug the ADR calls out by name.
    """
    deleted_at = _max_wins(incoming.get("deleted_at"), existing.get("deleted_at"))
    if deleted_at is None:
        merged["deleted_at"] = None
        return merged

    live_updated_at = None
    for side in (incoming, existing):
        if side.get("deleted_at") is None:
            live_updated_at = _max_wins(live_updated_at, side.get("updated_at"))

    if live_updated_at is not None and live_updated_at > deleted_at:
        merged["deleted_at"] = None  # resurrected by a strictly later upsert
    else:
        merged["deleted_at"] = deleted_at
    return merged


def merge_row(
    *,
    policy: MergePolicy,
    incoming: dict[str, Any],
    existing: dict[str, Any] | None,
    op: SyncOp,
    server_time: datetime,
) -> MergeOutcome:
    """Merge one incoming row against the stored one.

    Matrix coverage: rules 1-8 and the field strategies used by 9-22 (the
    per-entity halves of those rows live in their `MergePolicy`).
    """
    updated_at = incoming.get("updated_at")

    # Rule 6 -- a client clock more than 24h ahead is not merged at all.
    if updated_at is not None and updated_at > server_time + timedelta(
        hours=FUTURE_TOLERANCE_HOURS
    ):
        return _rejected(RejectReason.updated_at_in_future)

    incoming = _normalise_created_at(incoming)  # rule 7

    if op is SyncOp.delete and incoming.get("deleted_at") is None:
        # A delete whose payload forgot the tombstone still tombstones.
        incoming = {**incoming, "deleted_at": updated_at}

    if existing is None:
        merged = dict(incoming)
        merged = _resolve_deletion(merged, incoming, {"deleted_at": None, "updated_at": None})
        return MergeOutcome(status=ChangeStatus.applied, row=merged)

    # Rule 22 -- append-only entities: the first insert by `id` stands, a
    # repeat is a no-op and never a conflict.
    if policy.append_only:
        return MergeOutcome(status=ChangeStatus.applied, row=dict(existing))

    incoming_updated = incoming.get("updated_at")
    existing_updated = existing.get("updated_at")

    if incoming_updated is not None and (
        existing_updated is None or incoming_updated > existing_updated
    ):
        winner = incoming  # rule 1 -- client wins
    elif existing_updated is not None and (
        incoming_updated is None or incoming_updated < existing_updated
    ):
        winner = existing  # rule 2 -- server wins
    elif _comparable(incoming, policy) == _comparable(existing, policy):
        # Rule 3 -- equal `updated_at`, byte-identical payload: no-op.
        return MergeOutcome(status=ChangeStatus.applied, row=dict(existing))
    else:
        winner = existing  # rule 4 -- equal `updated_at`, differing payload

    merged = dict(winner)
    for rule in policy.field_rules:
        _apply_field_rule(rule, merged=merged, winner=winner, incoming=incoming, existing=existing)

    merged["updated_at"] = _max_wins(incoming_updated, existing_updated)
    created = [row.get("created_at") for row in (incoming, existing) if row.get("created_at")]
    if created:
        merged["created_at"] = min(created)
    merged = _resolve_deletion(merged, incoming, existing)  # rule 5

    status = (
        ChangeStatus.applied
        if _comparable(merged, policy) == _comparable(incoming, policy)
        else ChangeStatus.conflict
    )
    return MergeOutcome(status=status, row=merged)


def natural_key_of(policy: MergePolicy, row: dict[str, Any]) -> tuple[Any, ...] | None:
    """The row's natural key, with the ADR's `coalesce(ref_id, '')` semantics."""
    if not policy.natural_key:
        return None
    return tuple(row.get(column) or "" for column in policy.natural_key)


def natural_key_survivor(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    """ADR rule 14: smaller `created_at` survives; tie -> lexicographically smaller `id`."""
    left_key = (left.get("created_at"), str(left.get("id")))
    right_key = (right.get("created_at"), str(right.get("id")))
    return left if left_key <= right_key else right


def merge_natural_key_collision(
    *,
    policy: MergePolicy,
    incoming: dict[str, Any],
    other: dict[str, Any],
    op: SyncOp,
    server_time: datetime,
) -> MergeOutcome:
    """ADR rule 14 -- two devices minted different UUIDs for one natural key.

    Fields are merged by rules 9-13 (i.e. by `policy`), the survivor keeps the
    id chosen by `natural_key_survivor`, and the caller tombstones the loser
    with a `merged_into` marker. The answer is always `conflict`: whichever
    device pushed, at least one id it knows about changed meaning.
    """
    outcome = merge_row(
        policy=policy,
        incoming=incoming,
        existing=other,
        op=op,
        server_time=server_time,
    )
    if outcome.rejected or outcome.row is None:
        return outcome

    survivor = natural_key_survivor(incoming, other)
    merged = dict(outcome.row)
    merged["id"] = survivor["id"]
    merged["created_at"] = min(
        value for value in (incoming.get("created_at"), other.get("created_at")) if value
    )
    return MergeOutcome(status=ChangeStatus.conflict, row=merged)


# --- normative per-entity policies (ADR matrix rows 8-22) -------------------
#
# A Phase-2 feature module may point `SyncEntity.policy` straight at one of
# these instead of retyping the ADR. They are data, not behaviour: the engine
# above is the only interpreter.

_LOG_NATURAL_KEY_NOTE = "ADR rule 16: each log table documents its own ref_id meaning."

ADR_ENTITY_POLICIES: dict[str, MergePolicy] = {
    # Rule 8 -- tasks: completed_at max-wins, `completed` is not synced at all.
    "tasks": MergePolicy(
        adr_rules=(8,),
        field_rules=(FieldRule("completed_at", MergeStrategy.max_wins, adr_rule=8),),
        ignored_fields=("completed",),
    ),
    # Rule 9 -- habit_logs: NK (user_id, habit_id, date); count/value max-wins.
    "habit_logs": MergePolicy(
        adr_rules=(9, 14),
        natural_key=("user_id", "ref_id", "date"),
        field_rules=(
            FieldRule("count", MergeStrategy.max_wins, adr_rule=9),
            FieldRule("value", MergeStrategy.max_wins, adr_rule=9),
            FieldRule("note", MergeStrategy.lww, adr_rule=9),
        ),
    ),
    # Rule 10 -- prayer_logs: NK (user_id, prayer_key, date); ordered enum max-wins.
    "prayer_logs": MergePolicy(
        adr_rules=(10, 14),
        natural_key=("user_id", "ref_id", "date"),
        field_rules=(
            FieldRule(
                "status",
                MergeStrategy.enum_max_wins,
                adr_rule=10,
                enum_order=("none", "qaza", "alone", "jamaah"),
            ),
            FieldRule("note", MergeStrategy.lww, adr_rule=10),
        ),
    ),
    # Rule 11 -- mood_logs: score/note LWW, tags are a union.
    "mood_logs": MergePolicy(
        adr_rules=(11, 14),
        natural_key=("user_id", "ref_id", "date"),
        field_rules=(
            FieldRule("score", MergeStrategy.lww, adr_rule=11),
            FieldRule("note", MergeStrategy.lww, adr_rule=11),
            FieldRule("tags", MergeStrategy.set_union, adr_rule=11, max_items=SLUG_LIST_MAX_ITEMS),
        ),
    ),
    # Rule 12 -- sleep_logs: bed/wake move as a pair, duration is derived;
    # quality and note are plain LWW.
    "sleep_logs": MergePolicy(
        adr_rules=(12, 14),
        natural_key=("user_id", "ref_id", "date"),
        field_rules=(
            FieldRule("bed_time", MergeStrategy.grouped_lww, adr_rule=12, group="sleep_window"),
            FieldRule("wake_time", MergeStrategy.grouped_lww, adr_rule=12, group="sleep_window"),
            FieldRule("duration_min", MergeStrategy.derived, adr_rule=12, group="sleep_window"),
            FieldRule("quality", MergeStrategy.lww, adr_rule=12),
            FieldRule("note", MergeStrategy.lww, adr_rule=12),
        ),
    ),
    # Rule 13 -- health_logs: additive fields max-wins, weight/note LWW.
    "health_logs": MergePolicy(
        adr_rules=(13, 14),
        natural_key=("user_id", "ref_id", "date"),
        field_rules=(
            FieldRule("water_ml", MergeStrategy.max_wins, adr_rule=13),
            FieldRule("steps", MergeStrategy.max_wins, adr_rule=13),
            FieldRule("workout_min", MergeStrategy.max_wins, adr_rule=13),
            FieldRule("calories", MergeStrategy.max_wins, adr_rule=13),
            FieldRule("weight_kg", MergeStrategy.lww, adr_rule=13),
            FieldRule("note", MergeStrategy.lww, adr_rule=13),
        ),
    ),
    # Rule 25 -- family_logs (appended after 1-24): time with family is
    # additive, activities are a union, the note is LWW; rule 14 applies.
    "family_logs": MergePolicy(
        adr_rules=(25, 14),
        natural_key=("user_id", "ref_id", "date"),
        field_rules=(
            FieldRule("minutes", MergeStrategy.max_wins, adr_rule=25),
            FieldRule(
                "activities", MergeStrategy.set_union, adr_rule=25, max_items=SLUG_LIST_MAX_ITEMS
            ),
            FieldRule("note", MergeStrategy.lww, adr_rule=25),
        ),
    ),
    # Rules 15 & 16 -- quran_progress: one row per user, totals never shrink.
    "quran_progress": MergePolicy(
        adr_rules=(15, 16),
        natural_key=("user_id",),
        field_rules=(
            FieldRule("last_ayah_key", MergeStrategy.lww, adr_rule=15),
            FieldRule("pages_read_total", MergeStrategy.max_wins, adr_rule=16),
            FieldRule("ayahs_read_total", MergeStrategy.max_wins, adr_rule=16),
            FieldRule("khatm_count", MergeStrategy.max_wins, adr_rule=16),
        ),
    ),
    # Rule 17 -- quran_bookmarks: plain LWW + soft delete.
    "quran_bookmarks": MergePolicy(adr_rules=(17,)),
    # Rule 18 -- goals/milestones: LWW; progress_percent is explicitly *not* max-wins.
    "goals": MergePolicy(
        adr_rules=(18,),
        field_rules=(FieldRule("progress_percent", MergeStrategy.lww, adr_rule=18),),
    ),
    "milestones": MergePolicy(
        adr_rules=(18,),
        field_rules=(FieldRule("progress_percent", MergeStrategy.lww, adr_rule=18),),
    ),
    # Rule 19 -- preferences: one row per user, whole-row LWW, no field merge.
    "preferences": MergePolicy(adr_rules=(19,), natural_key=("user_id",)),
    # Rule 20 -- plain LWW + soft delete.
    "task_categories": MergePolicy(adr_rules=(20,)),
    "calendar_events": MergePolicy(adr_rules=(20,)),
    "habits": MergePolicy(adr_rules=(20,)),
    "education_items": MergePolicy(adr_rules=(20,)),
    "books": MergePolicy(adr_rules=(20,)),
    "app_limits": MergePolicy(adr_rules=(20,)),
    # Rule 21 -- digital wellbeing rollups: upload-only, additive max-wins.
    "dw_daily": MergePolicy(
        adr_rules=(21,),
        natural_key=("user_id", "date", "app_key"),
        field_rules=(
            FieldRule("minutes", MergeStrategy.max_wins, adr_rule=21),
            FieldRule("sessions", MergeStrategy.max_wins, adr_rule=21),
            FieldRule("waste_minutes_est", MergeStrategy.max_wins, adr_rule=21),
        ),
    ),
    "dw_score": MergePolicy(
        adr_rules=(21,),
        natural_key=("user_id", "date"),
        field_rules=(FieldRule("score", MergeStrategy.max_wins, adr_rule=21),),
    ),
    # Rule 22 -- dw_events: append-only, idempotent by id, never a conflict.
    "dw_events": MergePolicy(adr_rules=(22,), append_only=True),
}
