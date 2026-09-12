/// Pure, screen-facing derived values for a [Goal] and its [Milestone]s.
/// Nothing here touches the database or Riverpod — see
/// `application/goals_providers.dart` for the reactive wiring, and
/// `data/goal_repository.dart`'s class doc for why
/// [Goal.progressPercent] is never clamped or floored.
library;

import '../../../core/db/app_database.dart' show Goal, Milestone;

/// Percentage (0-100, rounded to the nearest whole number) of [milestones]
/// that are completed (`completedAt != null`), counting only non-deleted
/// milestones. `null` when there are no live milestones to roll up —
/// distinct from "0% done", which means there ARE milestones and none of
/// them are complete.
///
/// **Display precedence:** this is NOT what a screen should show as "the"
/// goal's progress — [Goal.progressPercent] is (see that field's own
/// doc). Why: sync-conflict-matrix rule 18 makes `progress_percent` a
/// plain last-write-wins field the user (or a future device/app version)
/// may set directly, including backwards — a goal is allowed to regress.
/// If a screen silently replaced that value with this milestone rollup
/// instead, it would (a) fight the user's/another device's explicit
/// input on the very next rebuild, effectively re-introducing a
/// client-side derivation the ADR forbids, and (b) leave a goal with zero
/// milestones unable to show any progress at all. [computeMilestoneProgressPercent]
/// exists so a screen MAY show it as a secondary "N/M milestones done"
/// indicator alongside the real number, never in place of it.
int? computeMilestoneProgressPercent(List<Milestone> milestones) {
  final live = milestones.where((m) => m.deletedAt == null).toList();
  if (live.isEmpty) return null;
  final completed = live.where((m) => m.completedAt != null).length;
  return ((completed / live.length) * 100).round();
}

int _wholeDaysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Whole days from [now] to [targetDate], at day granularity — "3pm
/// today" and "9am today" both count as day 0, not a fractional
/// `Duration`. `null` when the goal has no target date at all. Negative
/// once the target date is in the past (an overdue goal).
int? computeDaysRemaining(DateTime? targetDate, DateTime now) {
  if (targetDate == null) return null;
  return _wholeDaysBetween(now, targetDate);
}

/// Whether a goal is "at risk", derived purely from data already on the
/// device — no server round trip, and no user-visible text (a later
/// screen task decides how to phrase this). A goal is at risk when:
/// - it has a [targetDate] that has already passed and it isn't done
///   ([progressPercent] < 100), OR
/// - it has a [targetDate] still ahead, but [progressPercent] is lagging
///   more than [laggingThresholdPercent] percentage points behind the
///   *linear* pace needed to reach 100% by [targetDate], measured from
///   [createdAt].
///
/// A goal with no [targetDate] is never "at risk" — there is nothing in
/// the data to measure risk against, and this function does not invent
/// one. A goal already at/above 100% is never "at risk" either, even if
/// overdue (it's done).
bool isGoalAtRisk({
  required DateTime? targetDate,
  required DateTime createdAt,
  required int progressPercent,
  required DateTime now,
  int laggingThresholdPercent = 20,
}) {
  if (targetDate == null || progressPercent >= 100) return false;

  final remaining = _wholeDaysBetween(now, targetDate);
  if (remaining < 0) return true; // overdue and incomplete

  final totalDays = _wholeDaysBetween(createdAt, targetDate);
  if (totalDays <= 0) {
    // The target date is on/before the goal's own creation day — the only
    // signal left is whether today is that day and it's still incomplete.
    return remaining == 0;
  }
  final elapsedDays = totalDays - remaining;
  final expectedPercent = (elapsedDays / totalDays * 100).clamp(0, 100);
  return progressPercent < expectedPercent - laggingThresholdPercent;
}

/// Bundles the derived values above for one goal — the shape a
/// goal-detail screen actually wants, computed from a
/// `goalWithMilestonesProvider` emission
/// (`application/goals_providers.dart`).
class GoalProgressSummary {
  const GoalProgressSummary({
    required this.displayProgressPercent,
    required this.milestoneProgressPercent,
    required this.daysRemaining,
    required this.isAtRisk,
  });

  factory GoalProgressSummary.of(
    Goal goal,
    List<Milestone> milestones, {
    required DateTime now,
  }) {
    return GoalProgressSummary(
      displayProgressPercent: goal.progressPercent,
      milestoneProgressPercent: computeMilestoneProgressPercent(milestones),
      daysRemaining: computeDaysRemaining(goal.targetDate, now),
      isAtRisk: isGoalAtRisk(
        targetDate: goal.targetDate,
        createdAt: goal.createdAt,
        progressPercent: goal.progressPercent,
        now: now,
      ),
    );
  }

  /// The number to show as "the" progress — always [Goal.progressPercent]
  /// as it was when this summary was built, never [milestoneProgressPercent].
  final int displayProgressPercent;
  final int? milestoneProgressPercent;
  final int? daysRemaining;
  final bool isAtRisk;
}
