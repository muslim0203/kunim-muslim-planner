/// Wires the widgets and their logs into the daily analysis and the points.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../habits/application/habit_stats_providers.dart';
import '../../habits/domain/habit_schedule.dart';
import '../../habits/domain/local_day.dart';
import '../domain/activity_history.dart';
import '../domain/daily_score.dart';
import 'weekly_stats_provider.dart';

/// How many days the analysis looks back over.
const int activityWindowDays = 30;

/// Day-by-day: what each widget asked for and whether it was done. Empty
/// while the streams are still loading, so the screen shows an empty grid
/// rather than a spinner in the middle of the page.
final activityHistoryProvider = Provider<ActivityHistory>((ref) {
  final habits = ref.watch(activeHabitsProvider).value ?? const [];
  final logs = ref.watch(allHabitLogsProvider).value ?? const [];
  final today = ref.watch(statsTodayProvider);

  final countsByHabit = <String, Map<LocalDay, int>>{};
  for (final log in logs) {
    (countsByHabit[log.habitId] ??=
        <LocalDay, int>{})[LocalDay.fromUtcMidnight(log.date)] = log.count;
  }

  return ActivityHistory.compute(
    sources: [
      for (final habit in habits)
        ActivitySource(
          id: habit.id,
          title: habit.title,
          schedule: HabitSchedule.fromJson(habit.frequency),
          targetCount: habit.targetCount,
          createdOn: LocalDay.fromLocalDateTime(habit.createdAt.toLocal()),
          countsByDay: countsByHabit[habit.id] ?? const <LocalDay, int>{},
        ),
    ],
    today: today,
    length: activityWindowDays,
  );
});

final scoreBoardProvider = Provider<ScoreBoard>((ref) {
  return ScoreBoard.compute(ref.watch(activityHistoryProvider));
});
