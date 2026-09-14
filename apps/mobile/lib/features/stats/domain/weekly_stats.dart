/// Weekly statistics computed purely from what is stored on this device.
///
/// Nothing here is estimated or invented: every number is derived from task
/// and habit rows. Areas the app does not track yet (prayer, Qur'an, health,
/// sleep) are intentionally absent — the screen marks them as coming soon
/// instead of showing placeholder figures.
///
/// Counting rules (a "day" is a local calendar day):
/// - A task with a due date counts on its due day; it is done if it has been
///   completed at any point (a late completion still counts as done).
/// - A task without a due date counts only on the day it was completed, as
///   planned and done at once — undated work still shows up as effort.
/// - An every-day / specific-weekday habit counts on each day it is
///   scheduled, from the day it was created; it is done when that day's
///   logged count reaches its target.
/// - A times-per-week habit has no fixed days, so it is counted against its
///   weekly quota for the whole window rather than day by day.
library;

import 'package:kunim/core/db/app_database.dart';

import '../../habits/domain/habit_schedule.dart';
import '../../habits/domain/local_day.dart';
import '../../habits/domain/streak.dart';

/// One habit's schedule and full log history, decoupled from Drift rows so
/// the computation stays trivially unit-testable.
class HabitHistory {
  const HabitHistory({
    required this.schedule,
    required this.targetCount,
    required this.createdOn,
    required this.countsByDay,
  });

  final HabitSchedule schedule;
  final int targetCount;
  final LocalDay createdOn;
  final Map<LocalDay, int> countsByDay;

  bool isDoneOn(LocalDay day) => (countsByDay[day] ?? 0) >= targetCount;

  bool get isWeeklyQuota => schedule.type == HabitScheduleType.timesPerWeek;
}

class DayTally {
  const DayTally(
      {required this.day, required this.planned, required this.done});

  final LocalDay day;
  final int planned;
  final int done;

  /// `null` when nothing was planned, so an empty day never looks like 0%.
  double? get ratio => planned == 0 ? null : done / planned;
}

class WeeklyStats {
  const WeeklyStats({
    required this.days,
    required this.tasksPlanned,
    required this.tasksDone,
    required this.habitsScheduled,
    required this.habitsDone,
    required this.consistencyPercent,
    required this.previousWeekPercent,
    required this.bestDay,
    required this.bestStreak,
    required this.bestStreakUnit,
  });

  /// The last seven local days, oldest first, ending today.
  final List<DayTally> days;

  final int tasksPlanned;
  final int tasksDone;
  final int habitsScheduled;
  final int habitsDone;

  /// Share of planned items that were done this week, or `null` if nothing
  /// was planned.
  final int? consistencyPercent;

  /// The same figure for the seven days before, or `null` if nothing was
  /// planned then.
  final int? previousWeekPercent;

  /// The day with the best completion ratio (ties go to more items done,
  /// then to the most recent day), or `null` if nothing was planned.
  final DayTally? bestDay;

  /// The longest current streak among active habits; 0 when there is none.
  final int bestStreak;
  final StreakUnit? bestStreakUnit;

  bool get hasData => tasksPlanned + habitsScheduled > 0;

  static WeeklyStats compute({
    required List<Task> tasks,
    required List<HabitHistory> habits,
    required LocalDay today,
  }) {
    final liveTasks = tasks.where((task) => task.deletedAt == null).toList();
    final week = _Window(start: today.addDays(-6), end: today);
    final previous = _Window(start: today.addDays(-13), end: today.addDays(-7));

    final current = _tallyWindow(week, liveTasks, habits);
    final before = _tallyWindow(previous, liveTasks, habits);

    DayTally? best;
    for (final day in current.days) {
      final ratio = day.ratio;
      if (ratio == null) continue;
      final bestRatio = best?.ratio;
      if (best == null ||
          bestRatio == null ||
          ratio > bestRatio ||
          (ratio == bestRatio && day.done >= best.done)) {
        best = day;
      }
    }

    var bestDayStreak = 0;
    var bestWeekStreak = 0;
    for (final habit in habits) {
      final completedDays = {
        for (final entry in habit.countsByDay.entries)
          if (entry.value >= habit.targetCount) entry.key,
      };
      final result = Streak.compute(
        schedule: habit.schedule,
        completedDays: completedDays,
        today: today,
      );
      if (result.unit == StreakUnit.day) {
        if (result.current > bestDayStreak) bestDayStreak = result.current;
      } else if (result.current > bestWeekStreak) {
        bestWeekStreak = result.current;
      }
    }

    final (streak, unit) = bestDayStreak > 0
        ? (bestDayStreak, StreakUnit.day)
        : bestWeekStreak > 0
            ? (bestWeekStreak, StreakUnit.week)
            : (0, null);

    return WeeklyStats(
      days: current.days,
      tasksPlanned: current.tasksPlanned,
      tasksDone: current.tasksDone,
      habitsScheduled: current.habitsScheduled,
      habitsDone: current.habitsDone,
      consistencyPercent: current.percent,
      previousWeekPercent: before.percent,
      bestDay: best,
      bestStreak: streak,
      bestStreakUnit: unit,
    );
  }

  static _WindowTally _tallyWindow(
    _Window window,
    List<Task> tasks,
    List<HabitHistory> habits,
  ) {
    final days = <DayTally>[];
    var tasksPlanned = 0;
    var tasksDone = 0;
    var habitsScheduled = 0;
    var habitsDone = 0;

    for (var day = window.start;
        !day.isAfter(window.end);
        day = day.addDays(1)) {
      var planned = 0;
      var done = 0;

      for (final task in tasks) {
        final due = _localDayOf(task.dueDate);
        if (due != null) {
          if (due == day) {
            planned++;
            if (task.completedAt != null) done++;
          }
        } else if (_localDayOf(task.completedAt) == day) {
          planned++;
          done++;
        }
      }
      tasksPlanned += planned;
      tasksDone += done;

      for (final habit in habits) {
        if (day.isBefore(habit.createdOn)) continue;
        if (habit.isWeeklyQuota) {
          // Off days are not failures for a weekly quota; only a completed
          // day contributes to that day's tally.
          if (habit.isDoneOn(day)) {
            planned++;
            done++;
          }
          continue;
        }
        if (!habit.schedule.isScheduledOn(day)) continue;
        planned++;
        habitsScheduled++;
        if (habit.isDoneOn(day)) {
          done++;
          habitsDone++;
        }
      }

      days.add(DayTally(day: day, planned: planned, done: done));
    }

    for (final habit in habits.where((h) => h.isWeeklyQuota)) {
      var eligibleDays = 0;
      var doneDays = 0;
      for (var day = window.start;
          !day.isAfter(window.end);
          day = day.addDays(1)) {
        if (day.isBefore(habit.createdOn)) continue;
        eligibleDays++;
        if (habit.isDoneOn(day)) doneDays++;
      }
      if (eligibleDays == 0) continue;
      final quota = habit.schedule.timesPerWeek.clamp(1, eligibleDays);
      habitsScheduled += quota;
      habitsDone += doneDays > quota ? quota : doneDays;
    }

    final planned = tasksPlanned + habitsScheduled;
    final done = tasksDone + habitsDone;
    return _WindowTally(
      days: days,
      tasksPlanned: tasksPlanned,
      tasksDone: tasksDone,
      habitsScheduled: habitsScheduled,
      habitsDone: habitsDone,
      percent: planned == 0 ? null : (done * 100 / planned).round(),
    );
  }

  static LocalDay? _localDayOf(DateTime? moment) =>
      moment == null ? null : LocalDay.fromLocalDateTime(moment.toLocal());
}

class _Window {
  const _Window({required this.start, required this.end});
  final LocalDay start;
  final LocalDay end;
}

class _WindowTally {
  const _WindowTally({
    required this.days,
    required this.tasksPlanned,
    required this.tasksDone,
    required this.habitsScheduled,
    required this.habitsDone,
    required this.percent,
  });

  final List<DayTally> days;
  final int tasksPlanned;
  final int tasksDone;
  final int habitsScheduled;
  final int habitsDone;
  final int? percent;
}
