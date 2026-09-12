/// "Habits for today": every active habit that is scheduled for the
/// current local calendar day, with today's progress attached.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../domain/habit_schedule.dart';
import '../domain/local_day.dart';
import 'habit_repositories.dart';

/// One habit's state for a single day — typed, no UI strings. [isDone] is
/// derived, never stored: `loggedCount >= habit.targetCount`.
class HabitToday {
  const HabitToday({
    required this.habit,
    required this.schedule,
    required this.day,
    required this.loggedCount,
  });

  final Habit habit;
  final HabitSchedule schedule;
  final LocalDay day;

  /// The day's logged `count` (0 if nothing logged yet). Per ADR-0002 rule
  /// 9, this is this device's locally-known count; it can be superseded
  /// by a higher value from another device after the next sync.
  final int loggedCount;

  bool get isDone => loggedCount >= habit.targetCount;
}

/// Active habits scheduled for [LocalDay.now()], each with today's
/// progress. Reactive — re-emits whenever a habit or today's logs change.
///
/// Known limitation: "today" is computed once when this provider builds a
/// new stream subscription, not re-evaluated on a timer — it only advances
/// past local midnight the next time something else causes this provider
/// to rebuild (e.g. app resume creating a new `ProviderContainer` scope,
/// or a manual `ref.invalidate`). Acceptable for phase 2: nothing in the
/// DoD requires live midnight rollover, and Drift's `watch()` has no
/// wall-clock trigger of its own to hook into instead.
final habitsForTodayProvider = StreamProvider<List<HabitToday>>((ref) {
  final repo = ref.watch(habitRepositoryProvider);
  final today = LocalDay.now();
  return repo.watchActiveHabitsWithLogOnDay(today).map((rows) {
    final result = <HabitToday>[];
    for (final row in rows) {
      final schedule = HabitSchedule.fromJson(row.habit.frequency);
      if (!schedule.isScheduledOn(today)) continue;
      result.add(
        HabitToday(
          habit: row.habit,
          schedule: schedule,
          day: today,
          loggedCount: row.log?.count ?? 0,
        ),
      );
    }
    return result;
  });
});
