/// The habit streak calculation — phase-2 DoD (`docs/plan.md` §12, phase-2
/// row: "streak 7/30/100 badge").
///
/// Pure functions over plain data only: no `AppDatabase`, no Riverpod, no
/// `DateTime.now()` read internally. [Streak.compute] takes "today" as an
/// explicit [LocalDay] argument (repositories/providers pass
/// [LocalDay.now()]; tests pass a fixed day), which is what makes this
/// file trivially unit-testable and keeps the timezone rule in exactly one
/// place (`domain/local_day.dart`).
///
/// ## Rules this file implements
///
/// - **Scheduled days only.** A day that [HabitSchedule.isScheduledOn]
///   says is not due for this habit is skipped entirely when walking
///   backwards — it neither extends nor breaks the streak. Only a
///   *scheduled* day with no completion breaks it.
/// - **Today in progress never breaks a streak.** If today is scheduled
///   but not yet completed, that is treated as "still in progress", not a
///   miss: it contributes nothing to the count, but walking further back
///   continues normally. Only a *past* scheduled day with no completion is
///   a genuine break. The same rule applies one level up for
///   [HabitScheduleType.timesPerWeek]: the current, not-yet-finished week
///   is never counted as a miss either.
/// - **Timezone / "day" identity.** Entirely delegated to [LocalDay] — see
///   its doc. This file never touches a raw `DateTime` directly.
/// - **What counts as "completed" is decided by the caller, not here.**
///   [Streak.compute] takes a `Set<LocalDay>` of already-completed days.
///   Building that set means comparing a day's logged `count` against the
///   habit's `targetCount` (`core/db/tables/habits_table.dart`) and
///   excluding tombstoned rows (ADR-0002 conflict-matrix rule 14) — both
///   are the data/application layer's job (see
///   `data/habit_log_repository.dart`), which keeps this file a pure
///   function of dates and free of rule 9's max-wins caveat: a local
///   decrement can never be "undone" by this file, because it never sees
///   raw counts at all.
library;

import 'habit_schedule.dart';
import 'local_day.dart';

/// The phase-2 DoD's three streak badges. Members are opaque identifiers —
/// any user-facing name/icon/copy lives in the presentation layer's ARB
/// files, never here (`CLAUDE.md`: UI text is never hardcoded).
enum StreakBadge { sevenStreak, thirtyStreak, hundredStreak }

extension StreakBadgeThreshold on StreakBadge {
  /// The streak length, in [StreakResult.unit]s, needed to earn this
  /// badge.
  int get threshold {
    switch (this) {
      case StreakBadge.sevenStreak:
        return 7;
      case StreakBadge.thirtyStreak:
        return 30;
      case StreakBadge.hundredStreak:
        return 100;
    }
  }
}

/// The unit [StreakResult.current] is counted in. Day-granular schedules
/// ([HabitScheduleType.everyDay], [HabitScheduleType.specificWeekdays])
/// count consecutive scheduled *days*; [HabitScheduleType.timesPerWeek]
/// has no fixed days to count, so it counts consecutive *weeks* that met
/// the weekly quota instead. The 7/30/100 badge thresholds apply to
/// whichever unit a given habit's streak is measured in — a
/// "times-per-week" habit's badges are earned in weeks, not days. This is
/// a deliberate scope decision (see class doc) rather than an oversight:
/// there is no single day-count definition of "streak" for a schedule that
/// has no particular days.
enum StreakUnit { day, week }

/// Result of [Streak.compute] for one habit.
class StreakResult {
  const StreakResult({
    required this.current,
    required this.unit,
    required this.badges,
  });

  /// The current streak length, in [unit]s.
  final int current;
  final StreakUnit unit;

  /// Every badge threshold [current] has reached (a habit at 45 has both
  /// [StreakBadge.sevenStreak] and [StreakBadge.thirtyStreak]).
  final Set<StreakBadge> badges;

  @override
  String toString() =>
      'StreakResult(current: $current, unit: $unit, badges: $badges)';
}

abstract final class Streak {
  /// A hard safety bound on how far back [compute] will ever walk (~12
  /// years of days, or the equivalent in weeks). It exists purely to
  /// guarantee termination for a pathological schedule that is never
  /// "due" on any day at all (e.g. [HabitSchedule.specificWeekdays] built
  /// directly — not via [HabitSchedule.fromJson], which never produces
  /// one — with an empty weekday set): without it, such a schedule would
  /// have [HabitSchedule.isScheduledOn] return `false` forever and the
  /// backward walk would never find a day to stop on. Any real habit
  /// resolves long before this bound.
  static const int _maxLookback = 365 * 12;

  /// Computes the current streak and earned badges for one habit.
  ///
  /// [completedDays] is the set of calendar days already known to satisfy
  /// this habit's target (see the class doc — building that set is the
  /// caller's job). [today] is the caller's current [LocalDay.now()] (or a
  /// fixed day in tests).
  static StreakResult compute({
    required HabitSchedule schedule,
    required Set<LocalDay> completedDays,
    required LocalDay today,
  }) {
    switch (schedule.type) {
      case HabitScheduleType.everyDay:
      case HabitScheduleType.specificWeekdays:
        final days = _dayStreak(
          schedule: schedule,
          completedDays: completedDays,
          today: today,
        );
        return StreakResult(
          current: days,
          unit: StreakUnit.day,
          badges: _badgesFor(days),
        );
      case HabitScheduleType.timesPerWeek:
        final weeks = _weekStreak(
          timesPerWeek: schedule.timesPerWeek,
          completedDays: completedDays,
          today: today,
        );
        return StreakResult(
          current: weeks,
          unit: StreakUnit.week,
          badges: _badgesFor(weeks),
        );
    }
  }

  static Set<StreakBadge> _badgesFor(int current) => {
        for (final badge in StreakBadge.values)
          if (current >= badge.threshold) badge,
      };

  static int _dayStreak({
    required HabitSchedule schedule,
    required Set<LocalDay> completedDays,
    required LocalDay today,
  }) {
    var cursor = today;
    var streak = 0;
    for (var i = 0; i < _maxLookback; i++) {
      if (!schedule.isScheduledOn(cursor)) {
        cursor = cursor.addDays(-1);
        continue;
      }
      if (completedDays.contains(cursor)) {
        streak++;
      } else if (cursor == today) {
        // Scheduled today, not completed yet: in progress, not a break.
      } else {
        break; // A scheduled day in the past with nothing logged: a break.
      }
      cursor = cursor.addDays(-1);
    }
    return streak;
  }

  static int _weekStreak({
    required int timesPerWeek,
    required Set<LocalDay> completedDays,
    required LocalDay today,
  }) {
    if (timesPerWeek <= 0) return 0;
    final currentWeekStart = today.mondayOfWeek;
    var weekStart = currentWeekStart;
    var streak = 0;
    for (var i = 0; i < _maxLookback; i++) {
      final isCurrentWeek = weekStart == currentWeekStart;
      // The current week is only "in progress" through today; a past week
      // is judged over its full 7 days.
      final weekEnd = isCurrentWeek ? today : weekStart.addDays(6);
      final completedInWeek = completedDays
          .where((d) => !d.isBefore(weekStart) && !d.isAfter(weekEnd))
          .length;
      if (completedInWeek >= timesPerWeek) {
        streak++;
      } else if (isCurrentWeek) {
        // This week isn't over yet: in progress, not a break.
      } else {
        break;
      }
      weekStart = weekStart.addDays(-7);
    }
    return streak;
  }
}
