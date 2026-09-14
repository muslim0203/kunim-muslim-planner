/// Wires local task and habit streams into [WeeklyStats].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../habits/application/habit_stats_providers.dart';
import '../../habits/domain/habit_schedule.dart';
import '../../habits/domain/local_day.dart';
import '../../tasks/application/task_providers.dart';
import '../domain/weekly_stats.dart';

/// "Today" for statistics. A provider so tests can pin the date.
final statsTodayProvider = Provider<LocalDay>((ref) => LocalDay.now());

final weeklyStatsProvider = Provider<AsyncValue<WeeklyStats>>((ref) {
  final tasksAsync = ref.watch(allTasksProvider);
  final habitsAsync = ref.watch(activeHabitsProvider);
  final logsAsync = ref.watch(allHabitLogsProvider);
  final today = ref.watch(statsTodayProvider);

  for (final value in <AsyncValue<Object?>>[
    tasksAsync,
    habitsAsync,
    logsAsync
  ]) {
    if (value.hasError) {
      return AsyncValue.error(
        value.error!,
        value.stackTrace ?? StackTrace.current,
      );
    }
  }

  final tasks = tasksAsync.value;
  final habits = habitsAsync.value;
  final logs = logsAsync.value;
  if (tasks == null || habits == null || logs == null) {
    return const AsyncValue.loading();
  }

  final countsByHabit = <String, Map<LocalDay, int>>{};
  for (final log in logs) {
    (countsByHabit[log.habitId] ??=
        <LocalDay, int>{})[LocalDay.fromUtcMidnight(log.date)] = log.count;
  }

  final histories = [
    for (final habit in habits)
      HabitHistory(
        schedule: HabitSchedule.fromJson(habit.frequency),
        targetCount: habit.targetCount,
        createdOn: LocalDay.fromLocalDateTime(habit.createdAt.toLocal()),
        countsByDay: countsByHabit[habit.id] ?? const <LocalDay, int>{},
      ),
  ];

  return AsyncValue.data(
    WeeklyStats.compute(tasks: tasks, habits: histories, today: today),
  );
});
