"""One numbered test per row of the ADR-0002 conflict matrix.

`docs/adr/0002-sync.md` ("Test majburiyati") requires at least one case per
matrix row, with the row number in the test name. The rows are driven through
`merge.py` directly because most of them describe entities whose tables are
Phase-2 work (T-202): the *rules* for those entities already exist as data in
`merge.ADR_ENTITY_POLICIES`, so they are testable today and a Phase-2 module
inherits behaviour that is already proven.

Rows that involve a real table as well are additionally driven end to end:
rules 1-5 and 14 through `test_sync_two_clients.py`, rules 6, 23 and 24
through `test_sync_protocol.py`, rules 8 and 14 through
`test_sync_entity_contract.py`.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from app.modules.sync.merge import (
    ADR_ENTITY_POLICIES,
    merge_natural_key_collision,
    merge_row,
    natural_key_of,
    precheck,
)
from app.modules.sync.registry import (
    MergePolicy,
    MergeStrategy,
    SyncDirection,
    SyncEntity,
)
from app.modules.sync.schemas import ChangeStatus, RejectReason, SyncOp, SyncRowBase

T0 = datetime(2026, 9, 12, 8, 0, 0, tzinfo=UTC)
USER = uuid.UUID("11111111-1111-4111-8111-111111111111")
OTHER_USER = uuid.UUID("22222222-2222-4222-8222-222222222222")
ROW = uuid.UUID("33333333-3333-4333-8333-333333333333")
LWW = MergePolicy()


def row(**overrides: Any) -> dict[str, Any]:
    base: dict[str, Any] = {
        "id": ROW,
        "user_id": USER,
        "created_at": T0,
        "updated_at": T0,
        "deleted_at": None,
        "server_version": 0,
    }
    base.update(overrides)
    return base


def entity(name: str, *, direction: SyncDirection = SyncDirection.bidirectional) -> SyncEntity:
    return SyncEntity(name=name, model=object, schema=SyncRowBase, direction=direction)


# --- rule 1 ------------------------------------------------------------------


def test_rule_01_newer_incoming_updated_at_wins_applied() -> None:
    incoming = row(updated_at=T0 + timedelta(minutes=5), server_version=1)
    existing = row(updated_at=T0, server_version=1)
    outcome = merge_row(
        policy=LWW, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.status is ChangeStatus.applied
    assert outcome.row["updated_at"] == T0 + timedelta(minutes=5)


# --- rule 2 ------------------------------------------------------------------


def test_rule_02_older_incoming_updated_at_loses_conflict_with_server_row() -> None:
    incoming = row(updated_at=T0, deleted_at=None)
    existing = row(updated_at=T0 + timedelta(minutes=5), server_version=7)
    outcome = merge_row(
        policy=LWW, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.status is ChangeStatus.conflict
    assert outcome.row["updated_at"] == T0 + timedelta(minutes=5)


# --- rules 3 & 4 -------------------------------------------------------------


def test_rule_03_equal_updated_at_identical_payload_is_a_noop_applied() -> None:
    incoming = row(updated_at=T0)
    existing = row(updated_at=T0, server_version=4)
    outcome = merge_row(
        policy=LWW, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.status is ChangeStatus.applied
    assert outcome.row["server_version"] == 4  # nothing changed


def test_rule_04_equal_updated_at_differing_payload_server_wins_conflict() -> None:
    policy = MergePolicy()
    incoming = row(updated_at=T0) | {"title": "from client"}
    existing = row(updated_at=T0) | {"title": "from server"}
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.status is ChangeStatus.conflict
    assert outcome.row["title"] == "from server"  # deterministic tie-break


# --- rule 5 ------------------------------------------------------------------


def test_rule_05_soft_delete_beats_a_concurrent_older_update() -> None:
    incoming = row(updated_at=T0 + timedelta(minutes=1))  # a live edit
    existing = row(updated_at=T0 + timedelta(minutes=5), deleted_at=T0 + timedelta(minutes=5))
    outcome = merge_row(
        policy=LWW, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.status is ChangeStatus.conflict
    assert outcome.row["deleted_at"] == T0 + timedelta(minutes=5)


def test_rule_05_delete_wins_even_when_its_updated_at_is_older() -> None:
    """The ADR is explicit: the delete wins "regardless of LWW"."""
    incoming = row(updated_at=T0 + timedelta(minutes=9), deleted_at=T0 + timedelta(minutes=9))
    existing = row(updated_at=T0 + timedelta(minutes=9))
    outcome = merge_row(
        policy=LWW, incoming=incoming, existing=existing, op=SyncOp.delete, server_time=T0
    )
    assert outcome.row["deleted_at"] == T0 + timedelta(minutes=9)


def test_rule_05_resurrection_requires_an_upsert_strictly_after_deleted_at() -> None:
    incoming = row(updated_at=T0 + timedelta(minutes=10), deleted_at=None)
    existing = row(updated_at=T0 + timedelta(minutes=5), deleted_at=T0 + timedelta(minutes=5))
    outcome = merge_row(
        policy=LWW, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.status is ChangeStatus.applied
    assert outcome.row["deleted_at"] is None


# --- rule 6 ------------------------------------------------------------------


def test_rule_06_updated_at_more_than_24h_ahead_is_rejected() -> None:
    incoming = row(updated_at=T0 + timedelta(hours=24, minutes=1))
    outcome = merge_row(
        policy=LWW, incoming=incoming, existing=None, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.status is ChangeStatus.rejected
    assert outcome.reason is RejectReason.updated_at_in_future


def test_rule_06_exactly_24h_ahead_is_still_accepted() -> None:
    incoming = row(updated_at=T0 + timedelta(hours=24))
    outcome = merge_row(
        policy=LWW, incoming=incoming, existing=None, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.status is ChangeStatus.applied


# --- rule 7 ------------------------------------------------------------------


def test_rule_07_created_at_after_updated_at_is_normalised_not_rejected() -> None:
    incoming = row(created_at=T0 + timedelta(hours=1), updated_at=T0)
    outcome = merge_row(
        policy=LWW, incoming=incoming, existing=None, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.status is ChangeStatus.applied
    assert outcome.row["created_at"] == T0


def test_rule_07_created_at_takes_the_minimum_of_both_sides() -> None:
    incoming = row(created_at=T0 + timedelta(hours=2), updated_at=T0 + timedelta(hours=3))
    existing = row(created_at=T0, updated_at=T0 + timedelta(hours=1))
    outcome = merge_row(
        policy=LWW, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.row["created_at"] == T0
    # Normalising `created_at` never turns an otherwise clean write into a conflict.
    assert outcome.status is ChangeStatus.applied


# --- rule 8 ------------------------------------------------------------------


def test_rule_08_tasks_completed_at_is_max_wins() -> None:
    policy = ADR_ENTITY_POLICIES["tasks"]
    later = T0 + timedelta(hours=2)
    incoming = row(updated_at=T0 + timedelta(minutes=10), completed_at=None)
    existing = row(updated_at=T0, completed_at=later)
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    # The client is newer, but sync never un-completes a task.
    assert outcome.row["completed_at"] == later
    assert outcome.status is ChangeStatus.conflict


def test_rule_08_tasks_completed_flag_is_never_synced() -> None:
    policy = ADR_ENTITY_POLICIES["tasks"]
    assert "completed" in policy.ignored_fields
    incoming = row(updated_at=T0, completed=True, completed_at=None)
    existing = row(updated_at=T0, completed=False, completed_at=None)
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    # Equal `updated_at`, and the only difference is the derived flag -> no-op.
    assert outcome.status is ChangeStatus.applied


# --- rule 9 ------------------------------------------------------------------


def test_rule_09_habit_logs_count_and_value_are_max_wins_note_is_lww() -> None:
    policy = ADR_ENTITY_POLICIES["habit_logs"]
    assert policy.natural_key == ("user_id", "ref_id", "date")
    incoming = row(updated_at=T0 + timedelta(minutes=5), count=2, value=1.0, note="client")
    existing = row(updated_at=T0, count=7, value=9.5, note="server")
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.row["count"] == 7
    assert outcome.row["value"] == 9.5
    assert outcome.row["note"] == "client"  # LWW winner
    assert outcome.status is ChangeStatus.conflict


# --- rule 10 -----------------------------------------------------------------


def test_rule_10_prayer_logs_status_is_ordered_enum_max_wins() -> None:
    policy = ADR_ENTITY_POLICIES["prayer_logs"]
    rule = policy.rules_for_adr(10)[0]
    assert rule.strategy is MergeStrategy.enum_max_wins
    assert rule.enum_order == ("none", "qaza", "alone", "jamaah")

    incoming = row(updated_at=T0 + timedelta(minutes=5), status="qaza", note="c")
    existing = row(updated_at=T0, status="jamaah", note="s")
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.row["status"] == "jamaah"  # the higher rank survives
    assert outcome.row["note"] == "c"


# --- rule 11 -----------------------------------------------------------------


def test_rule_11_mood_logs_tags_are_unioned_score_is_lww() -> None:
    policy = ADR_ENTITY_POLICIES["mood_logs"]
    incoming = row(updated_at=T0 + timedelta(minutes=5), score=2, tags=["calm", "tired"])
    existing = row(updated_at=T0, score=5, tags=["tired", "grateful"])
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.row["tags"] == ["calm", "grateful", "tired"]
    assert outcome.row["score"] == 2  # LWW, explicitly not additive


def test_rule_11_tag_union_over_the_limit_keeps_the_winner_then_the_sorted_loser() -> None:
    policy = ADR_ENTITY_POLICIES["mood_logs"]
    assert policy.rule_for("tags").max_items == 32
    winner_tags = [f"w{i:02d}" for i in range(31, -1, -1)]  # 32 items, deliberately unsorted
    loser_tags = [f"l{i:02d}" for i in range(32)]

    def merge(incoming_tags: list[str], existing_tags: list[str]) -> Any:
        return merge_row(
            policy=policy,
            incoming=row(updated_at=T0 + timedelta(minutes=5), score=3, tags=incoming_tags),
            existing=row(updated_at=T0, score=3, tags=existing_tags),
            op=SyncOp.upsert,
            server_time=T0,
        )

    # Two full 32-item lists: the (wire-valid) winner fills the cap on its own;
    # the survivors come back sorted, like any union.
    outcome = merge(winner_tags, loser_tags)
    assert outcome.row["tags"] == sorted(winner_tags)
    assert len(outcome.row["tags"]) == 32
    assert merge(winner_tags, loser_tags).row == outcome.row  # deterministic

    # A short winner survives whole and is topped up with the loser's items
    # in sorted order (l00..l28), however the loser's own list was ordered.
    outcome = merge(["zeta", "alpha", "mid"], list(reversed(loser_tags)))
    assert outcome.row["tags"] == sorted(["zeta", "alpha", "mid", *loser_tags[:29]])
    assert outcome.status is ChangeStatus.conflict

    # When the stored row is the LWW winner, its items are the ones kept whole.
    server_wins = merge_row(
        policy=policy,
        incoming=row(updated_at=T0, tags=loser_tags),
        existing=row(updated_at=T0 + timedelta(minutes=5), tags=["b", "a"]),
        op=SyncOp.upsert,
        server_time=T0,
    )
    assert server_wins.row["tags"] == sorted(["b", "a", *loser_tags[:30]])

    # The capped result is a fixed point: re-merging it with itself changes nothing.
    capped = outcome.row["tags"]
    assert merge(capped, capped).row["tags"] == capped

    # Within the limit nothing changes: the union is simply sorted.
    assert merge(["b"], ["a"]).row["tags"] == ["a", "b"]


def test_rule_25_family_activity_union_is_capped_like_rule_11_even_on_collision() -> None:
    policy = ADR_ENTITY_POLICIES["family_logs"]
    assert policy.rule_for("activities").max_items == 32
    newer = [f"b{i:02d}" for i in range(32)]
    outcome = merge_natural_key_collision(
        policy=policy,
        incoming=row(
            id=uuid.UUID("aaaaaaaa-0000-4000-8000-000000000011"),
            created_at=T0 + timedelta(minutes=5),
            updated_at=T0 + timedelta(minutes=5),
            activities=newer,
        ),
        other=row(
            id=uuid.UUID("bbbbbbbb-0000-4000-8000-000000000011"),
            created_at=T0,
            updated_at=T0,
            activities=[f"a{i:02d}" for i in range(32)],
        ),
        op=SyncOp.upsert,
        server_time=T0,
    )
    assert outcome.row["activities"] == newer


# --- rule 12 -----------------------------------------------------------------


def test_rule_12_sleep_logs_bed_and_wake_move_as_one_pair_duration_is_derived() -> None:
    policy = ADR_ENTITY_POLICIES["sleep_logs"]
    assert policy.group_members("sleep_window") == ("bed_time", "wake_time", "duration_min")

    incoming = row(
        updated_at=T0 + timedelta(minutes=5), bed_time="23:00", wake_time="06:00", duration_min=420
    )
    existing = row(updated_at=T0, bed_time="00:30", wake_time="09:00", duration_min=510)
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    # Both halves come from the same winner; duration is not max-wins (510 lost).
    assert (outcome.row["bed_time"], outcome.row["wake_time"]) == ("23:00", "06:00")
    assert outcome.row["duration_min"] == 420


def test_rule_12_sleep_logs_quality_and_note_are_lww() -> None:
    policy = ADR_ENTITY_POLICIES["sleep_logs"]
    assert policy.rule_for("quality").strategy is MergeStrategy.lww
    assert policy.rule_for("note").strategy is MergeStrategy.lww

    incoming = row(updated_at=T0, quality=1, note="restless")  # the older write
    existing = row(updated_at=T0 + timedelta(minutes=5), quality=4, note="rested")
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    # A worse rating is not "smaller wins" or "larger wins": the last writer's stands.
    assert (outcome.row["quality"], outcome.row["note"]) == (4, "rested")
    assert outcome.status is ChangeStatus.conflict


# --- rule 13 -----------------------------------------------------------------


def test_rule_13_health_logs_additive_fields_max_wins_weight_is_lww() -> None:
    policy = ADR_ENTITY_POLICIES["health_logs"]
    incoming = row(
        updated_at=T0 + timedelta(minutes=5),
        water_ml=500,
        steps=9000,
        workout_min=0,
        calories=100,
        weight_kg=71.0,
        note="client",
    )
    existing = row(
        updated_at=T0,
        water_ml=1500,
        steps=1200,
        workout_min=45,
        calories=2000,
        weight_kg=80.0,
        note="server",
    )
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.row["water_ml"] == 1500
    assert outcome.row["steps"] == 9000
    assert outcome.row["workout_min"] == 45
    assert outcome.row["calories"] == 2000
    assert outcome.row["weight_kg"] == 71.0  # LWW, not max
    assert outcome.row["note"] == "client"


# --- rule 14 -----------------------------------------------------------------


def test_rule_14_natural_key_collision_older_created_at_survives() -> None:
    policy = ADR_ENTITY_POLICIES["health_logs"]
    newer_id = uuid.UUID("aaaaaaaa-0000-4000-8000-000000000001")
    older_id = uuid.UUID("bbbbbbbb-0000-4000-8000-000000000002")
    incoming = row(
        id=newer_id,
        created_at=T0 + timedelta(minutes=5),
        updated_at=T0 + timedelta(minutes=5),
        water_ml=300,
    )
    other = row(id=older_id, created_at=T0, updated_at=T0, water_ml=800)
    outcome = merge_natural_key_collision(
        policy=policy, incoming=incoming, other=other, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.status is ChangeStatus.conflict
    assert outcome.row["id"] == older_id  # older created_at survives
    assert outcome.row["water_ml"] == 800  # fields merged per rule 13
    assert outcome.row["created_at"] == T0


def test_rule_14_natural_key_collision_ties_break_on_lexicographically_smaller_id() -> None:
    policy = ADR_ENTITY_POLICIES["habit_logs"]
    smaller = uuid.UUID("00000000-0000-4000-8000-000000000001")
    bigger = uuid.UUID("ffffffff-0000-4000-8000-000000000002")
    incoming = row(id=bigger, created_at=T0, updated_at=T0)
    other = row(id=smaller, created_at=T0, updated_at=T0)
    outcome = merge_natural_key_collision(
        policy=policy, incoming=incoming, other=other, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.row["id"] == smaller


def test_rule_14_natural_key_uses_coalesce_on_a_missing_ref_id() -> None:
    policy = ADR_ENTITY_POLICIES["mood_logs"]
    assert natural_key_of(policy, row(ref_id=None, date="2026-09-12")) == (
        USER,
        "",
        "2026-09-12",
    )
    assert natural_key_of(LWW, row()) is None


# --- rules 15 & 16 -----------------------------------------------------------


def test_rule_15_quran_progress_last_ayah_key_is_lww() -> None:
    policy = ADR_ENTITY_POLICIES["quran_progress"]
    assert policy.natural_key == ("user_id",)
    incoming = row(updated_at=T0 + timedelta(minutes=5), last_ayah_key="2:255", khatm_count=0)
    existing = row(updated_at=T0, last_ayah_key="18:10", khatm_count=0)
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.row["last_ayah_key"] == "2:255"


def test_rule_16_quran_progress_totals_are_max_wins() -> None:
    policy = ADR_ENTITY_POLICIES["quran_progress"]
    incoming = row(
        updated_at=T0 + timedelta(minutes=5),
        pages_read_total=10,
        ayahs_read_total=50,
        khatm_count=0,
    )
    existing = row(updated_at=T0, pages_read_total=604, ayahs_read_total=6236, khatm_count=1)
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.row["pages_read_total"] == 604
    assert outcome.row["ayahs_read_total"] == 6236
    assert outcome.row["khatm_count"] == 1  # a total never shrinks


# --- rule 17 -----------------------------------------------------------------


def test_rule_17_quran_bookmarks_are_plain_lww_with_soft_delete() -> None:
    policy = ADR_ENTITY_POLICIES["quran_bookmarks"]
    assert policy.field_rules == ()
    incoming = row(updated_at=T0 + timedelta(minutes=1), label="client")
    existing = row(updated_at=T0, label="server")
    assert (
        merge_row(
            policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
        ).row["label"]
        == "client"
    )
    deleted = merge_row(
        policy=policy,
        incoming=row(updated_at=T0 + timedelta(minutes=2)),
        existing=existing,
        op=SyncOp.delete,
        server_time=T0,
    )
    assert deleted.row["deleted_at"] == T0 + timedelta(minutes=2)


# --- rule 18 -----------------------------------------------------------------


def test_rule_18_goals_progress_percent_is_lww_not_max_wins() -> None:
    for name in ("goals", "milestones"):
        policy = ADR_ENTITY_POLICIES[name]
        assert policy.rules_for_adr(18)[0].strategy is MergeStrategy.lww
        incoming = row(updated_at=T0 + timedelta(minutes=5), progress_percent=20)
        existing = row(updated_at=T0, progress_percent=90)
        outcome = merge_row(
            policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
        )
        assert outcome.row["progress_percent"] == 20  # a goal may move backwards


# --- rule 19 -----------------------------------------------------------------


def test_rule_19_preferences_is_whole_row_lww_with_no_field_merge() -> None:
    policy = ADR_ENTITY_POLICIES["preferences"]
    assert policy.field_rules == ()
    assert policy.natural_key == ("user_id",)
    incoming = row(updated_at=T0 + timedelta(minutes=1), ui={"theme": "dark"})
    existing = row(updated_at=T0, ui={"theme": "light"}, notifications={"prayer": False})
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    # The whole row is replaced, not merged key by key.
    assert outcome.row["ui"] == {"theme": "dark"}
    assert "notifications" not in outcome.row


# --- rule 20 -----------------------------------------------------------------


def test_rule_20_plain_lww_entities_have_no_field_rules() -> None:
    for name in (
        "task_categories",
        "calendar_events",
        "habits",
        "education_items",
        "books",
        "app_limits",
    ):
        policy = ADR_ENTITY_POLICIES[name]
        assert policy.field_rules == ()
        assert policy.adr_rules == (20,)
        outcome = merge_row(
            policy=policy,
            incoming=row(updated_at=T0 + timedelta(minutes=1), title="client"),
            existing=row(updated_at=T0, title="server"),
            op=SyncOp.upsert,
            server_time=T0,
        )
        assert outcome.row["title"] == "client"


# --- rule 21 -----------------------------------------------------------------


def test_rule_21_dw_rollups_are_max_wins_and_never_pulled() -> None:
    policy = ADR_ENTITY_POLICIES["dw_daily"]
    assert policy.natural_key == ("user_id", "date", "app_key")
    outcome = merge_row(
        policy=policy,
        incoming=row(updated_at=T0 + timedelta(minutes=5), minutes=10, sessions=1),
        existing=row(updated_at=T0, minutes=95, sessions=12),
        op=SyncOp.upsert,
        server_time=T0,
    )
    assert (outcome.row["minutes"], outcome.row["sessions"]) == (95, 12)

    upload_only = entity("dw_daily", direction=SyncDirection.upload_only)
    assert upload_only.pushable is True
    assert upload_only.pullable is False  # pull never returns these rows


# --- rule 22 -----------------------------------------------------------------


def test_rule_22_dw_events_are_append_only_and_never_conflict() -> None:
    policy = ADR_ENTITY_POLICIES["dw_events"]
    assert policy.append_only is True
    existing = row(updated_at=T0, kind="unlock")
    outcome = merge_row(
        policy=policy,
        incoming=row(updated_at=T0 + timedelta(hours=1), kind="tampered"),
        existing=existing,
        op=SyncOp.upsert,
        server_time=T0,
    )
    assert outcome.status is ChangeStatus.applied
    assert outcome.row["kind"] == "unlock"  # the first insert stands


# --- rule 23 -----------------------------------------------------------------


def test_rule_23_unknown_entity_is_rejected() -> None:
    assert precheck(entity=None, payload_user_id=None, jwt_user_id=USER) is (
        RejectReason.unknown_entity
    )


def test_rule_23_payload_for_another_user_is_rejected() -> None:
    assert (
        precheck(entity=entity("tasks"), payload_user_id=OTHER_USER, jwt_user_id=USER)
        is RejectReason.foreign_user
    )
    assert precheck(entity=entity("tasks"), payload_user_id=USER, jwt_user_id=USER) is None
    # A payload that omits `user_id` is fine: the server fills in the JWT subject.
    assert precheck(entity=entity("tasks"), payload_user_id=None, jwt_user_id=USER) is None


# --- rule 24 -----------------------------------------------------------------


def test_rule_24_pull_only_entity_push_is_rejected_readonly() -> None:
    content = entity("content", direction=SyncDirection.pull_only)
    assert (
        precheck(entity=content, payload_user_id=USER, jwt_user_id=USER)
        is RejectReason.readonly_entity
    )
    assert content.pushable is False


# --- rule 25 -----------------------------------------------------------------


def test_rule_25_family_logs_minutes_max_wins_activities_union_note_lww() -> None:
    policy = ADR_ENTITY_POLICIES["family_logs"]
    assert policy.natural_key == ("user_id", "ref_id", "date")
    assert policy.adr_rules == (25, 14)
    incoming = row(
        updated_at=T0 + timedelta(minutes=5),
        minutes=30,
        activities=["walk", "meal"],
        note="client",
    )
    existing = row(updated_at=T0, minutes=90, activities=["meal", "quran"], note="server")
    outcome = merge_row(
        policy=policy, incoming=incoming, existing=existing, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.row["minutes"] == 90  # additive: never shrinks
    assert outcome.row["activities"] == ["meal", "quran", "walk"]
    assert outcome.row["note"] == "client"  # LWW winner
    assert outcome.status is ChangeStatus.conflict


def test_rule_25_family_logs_natural_key_collision_merges_fields_per_rule_25() -> None:
    policy = ADR_ENTITY_POLICIES["family_logs"]
    newer_id = uuid.UUID("aaaaaaaa-0000-4000-8000-000000000025")
    older_id = uuid.UUID("bbbbbbbb-0000-4000-8000-000000000025")
    incoming = row(
        id=newer_id,
        created_at=T0 + timedelta(minutes=5),
        updated_at=T0 + timedelta(minutes=5),
        minutes=20,
        activities=["walk"],
    )
    other = row(id=older_id, created_at=T0, updated_at=T0, minutes=45, activities=["meal"])
    outcome = merge_natural_key_collision(
        policy=policy, incoming=incoming, other=other, op=SyncOp.upsert, server_time=T0
    )
    assert outcome.status is ChangeStatus.conflict
    assert outcome.row["id"] == older_id  # rule 14: older created_at survives
    assert outcome.row["minutes"] == 45
    assert outcome.row["activities"] == ["meal", "walk"]


# --- the matrix itself is data ----------------------------------------------

ADR_MATRIX_ROWS = 26
"""Rows in the ADR-0002 conflict matrix.

Rows 25 (`family_logs`) and 26 (`daily_scores`) were appended after 1-24.
"""


def test_every_adr_matrix_row_8_to_22_and_25_26_has_a_policy_entry() -> None:
    covered = {adr_rule for policy in ADR_ENTITY_POLICIES.values() for adr_rule in policy.adr_rules}
    assert covered >= (set(range(8, 23)) | {25, 26}) - {14}  # 14 is a cross-entity rule
    assert 14 in covered


def test_every_field_rule_carries_its_matrix_row_number() -> None:
    for policy in ADR_ENTITY_POLICIES.values():
        for rule in policy.field_rules:
            assert 1 <= rule.adr_rule <= ADR_MATRIX_ROWS, rule
