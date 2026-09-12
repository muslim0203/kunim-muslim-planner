/// A single habit's current streak and earned badges (`domain/streak.dart`
/// — the phase-2 DoD's 7/30/100 badges), kept live against the habit's
/// schedule/target and its log history.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/habit_schedule.dart';
import '../domain/local_day.dart';
import '../domain/streak.dart';
import 'habit_repositories.dart';

const _emptyStreak = StreakResult(
  current: 0,
  unit: StreakUnit.day,
  badges: <StreakBadge>{},
);

/// `null` habit (not found / archived) yields the empty streak rather
/// than an error — a habit disappearing mid-subscription (e.g. archived
/// from another screen) is a normal state transition, not a failure.
final habitStreakProvider = StreamProvider.family<StreakResult, String>((
  ref,
  habitId,
) {
  final habitRepo = ref.watch(habitRepositoryProvider);
  final logRepo = ref.watch(habitLogRepositoryProvider);

  return habitRepo.watchHabit(habitId).asyncExpand((habit) {
    if (habit == null) return Stream.value(_emptyStreak);

    final schedule = HabitSchedule.fromJson(habit.frequency);
    final targetCount = habit.targetCount;

    return logRepo.watchLogsForHabit(habitId).map((logs) {
      // What counts as "completed" is decided here, not in
      // `domain/streak.dart` (see that file's doc): a day's logged count
      // must meet the habit's target. `watchLogsForHabit` already
      // excludes tombstoned rows (rule 14).
      final completedDays = logs
          .where((log) => log.count >= targetCount)
          .map((log) => LocalDay.fromUtcMidnight(log.date))
          .toSet();
      return Streak.compute(
        schedule: schedule,
        completedDays: completedDays,
        today: LocalDay.now(),
      );
    });
  });
});
