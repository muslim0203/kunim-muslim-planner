import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/db/tables/tasks_table.dart' show TaskPriority;
import 'package:kunim/features/habits/domain/habit_schedule.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/habits/domain/streak.dart';
import 'package:kunim/features/stats/domain/weekly_stats.dart';

/// Monday, 14 September 2026.
const _today = LocalDay(2026, 9, 14);

DateTime _at(LocalDay day, [int hour = 10]) =>
    DateTime(day.year, day.month, day.day, hour);

Task _task(
  String id, {
  LocalDay? due,
  LocalDay? completed,
  bool deleted = false,
}) {
  final stamp = _at(_today);
  return Task(
    id: id,
    createdAt: stamp,
    updatedAt: stamp,
    deletedAt: deleted ? stamp : null,
    serverVersion: 0,
    dirty: false,
    title: id,
    priority: TaskPriority.medium,
    dueDate: due == null ? null : _at(due, 9),
    completedAt: completed == null ? null : _at(completed, 18),
  );
}

HabitHistory _habit({
  HabitSchedule schedule = const HabitSchedule.everyDay(),
  int target = 1,
  LocalDay? createdOn,
  Iterable<LocalDay> doneOn = const [],
}) {
  return HabitHistory(
    schedule: schedule,
    targetCount: target,
    createdOn: createdOn ?? _today.addDays(-60),
    countsByDay: {for (final day in doneOn) day: target},
  );
}

WeeklyStats _compute({
  List<Task> tasks = const [],
  List<HabitHistory> habits = const [],
}) =>
    WeeklyStats.compute(tasks: tasks, habits: habits, today: _today);

void main() {
  test('no activity yields no numbers at all, never zeros dressed as data', () {
    final stats = _compute();

    expect(stats.hasData, isFalse);
    expect(stats.consistencyPercent, isNull);
    expect(stats.previousWeekPercent, isNull);
    expect(stats.bestDay, isNull);
    expect(stats.bestStreak, 0);
    expect(stats.bestStreakUnit, isNull);
    expect(stats.days, hasLength(7));
    expect(stats.days.first.day, _today.addDays(-6));
    expect(stats.days.last.day, _today);
  });

  group('tasks', () {
    test('count on their due day, and a completed one counts as done', () {
      final stats = _compute(
        tasks: [
          _task('a', due: _today, completed: _today),
          _task('b', due: _today),
          _task('c', due: _today.addDays(-1), completed: _today),
        ],
      );

      expect(stats.tasksPlanned, 3);
      expect(stats.tasksDone, 2);
      expect(stats.consistencyPercent, 67);
    });

    test('older work lands in the previous week, not this one', () {
      final stats = _compute(
        tasks: [
          _task('old', due: _today.addDays(-8), completed: _today.addDays(-8)),
        ],
      );

      expect(stats.hasData, isFalse);
      expect(stats.consistencyPercent, isNull);
      expect(stats.previousWeekPercent, 100);
    });

    test('an undated task counts only on the day it was completed', () {
      final stats = _compute(
        tasks: [
          _task('done-undated', completed: _today),
          _task('open-undated'),
        ],
      );

      expect(stats.tasksPlanned, 1);
      expect(stats.tasksDone, 1);
    });

    test('deleted tasks are ignored', () {
      final stats = _compute(
        tasks: [_task('gone', due: _today, completed: _today, deleted: true)],
      );

      expect(stats.hasData, isFalse);
    });
  });

  group('habits', () {
    test('an every-day habit counts from the day it was created', () {
      final stats = _compute(
        habits: [
          _habit(
            createdOn: _today.addDays(-2),
            doneOn: [_today, _today.addDays(-1)],
          ),
        ],
      );

      expect(stats.habitsScheduled, 3);
      expect(stats.habitsDone, 2);
    });

    test('a specific-weekday habit counts only on those weekdays', () {
      final stats = _compute(
        habits: [
          _habit(
            schedule: const HabitSchedule.specificWeekdays({DateTime.monday}),
            doneOn: [_today],
          ),
        ],
      );

      expect(stats.habitsScheduled, 1);
      expect(stats.habitsDone, 1);
      expect(stats.consistencyPercent, 100);
    });

    test('a times-per-week habit is measured against its weekly quota', () {
      final partly = _compute(
        habits: [
          _habit(
            schedule: const HabitSchedule.timesPerWeek(3),
            doneOn: [_today, _today.addDays(-3)],
          ),
        ],
      );
      expect(partly.habitsScheduled, 3);
      expect(partly.habitsDone, 2);

      final beyondQuota = _compute(
        habits: [
          _habit(
            schedule: const HabitSchedule.timesPerWeek(3),
            doneOn: [for (var i = 0; i < 5; i++) _today.addDays(-i)],
          ),
        ],
      );
      expect(beyondQuota.habitsDone, 3);
      expect(beyondQuota.consistencyPercent, 100);
    });

    test('a count below the target is not done', () {
      final stats = _compute(
        habits: [
          HabitHistory(
            schedule: const HabitSchedule.everyDay(),
            targetCount: 3,
            createdOn: _today,
            countsByDay: {_today: 2},
          ),
        ],
      );

      expect(stats.habitsScheduled, 1);
      expect(stats.habitsDone, 0);
    });

    test('the best streak comes from the habit streak rules', () {
      final doneDays = [for (var i = 0; i < 5; i++) _today.addDays(-i)];
      final stats = _compute(habits: [_habit(doneOn: doneDays)]);

      final expected = Streak.compute(
        schedule: const HabitSchedule.everyDay(),
        completedDays: doneDays.toSet(),
        today: _today,
      );
      expect(expected.current, greaterThan(0));
      expect(stats.bestStreak, expected.current);
      expect(stats.bestStreakUnit, StreakUnit.day);
    });
  });

  test('the best day has the highest completion ratio', () {
    final yesterday = _today.addDays(-1);
    final stats = _compute(
      tasks: [
        _task('y1', due: yesterday, completed: yesterday),
        _task('y2', due: yesterday, completed: yesterday),
        _task('t1', due: _today, completed: _today),
        _task('t2', due: _today),
      ],
    );

    expect(stats.bestDay?.day, yesterday);
    expect(stats.bestDay?.ratio, 1.0);
    expect(stats.bestDay?.done, 2);
  });
}
