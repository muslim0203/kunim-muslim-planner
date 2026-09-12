// Pure-Dart unit tests for `features/tasks/domain/task_ordering.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/db/tables/tasks_table.dart';
import 'package:kunim/features/tasks/domain/task_ordering.dart';

final _now = DateTime.utc(2026, 9, 12, 12);

Task _task({
  required String id,
  DateTime? dueDate,
  DateTime? completedAt,
  DateTime? deletedAt,
  DateTime? createdAt,
  TaskPriority priority = TaskPriority.medium,
}) {
  return Task(
    id: id,
    createdAt: createdAt ?? _now,
    updatedAt: createdAt ?? _now,
    deletedAt: deletedAt,
    serverVersion: 0,
    dirty: true,
    title: id,
    priority: priority,
    dueDate: dueDate,
    completedAt: completedAt,
  );
}

void main() {
  group('isInTodayList', () {
    test('false for a soft-deleted task', () {
      final task = _task(
        id: 'a',
        dueDate: _now,
        deletedAt: _now,
      );
      expect(isInTodayList(task, now: _now), isFalse);
    });

    test('false for a task with no due date', () {
      expect(isInTodayList(_task(id: 'a'), now: _now), isFalse);
    });

    test('true for a task due today', () {
      final task = _task(id: 'a', dueDate: _now);
      expect(isInTodayList(task, now: _now), isTrue);
    });

    test('true for an overdue task', () {
      final task = _task(
        id: 'a',
        dueDate: _now.subtract(const Duration(days: 3)),
      );
      expect(isInTodayList(task, now: _now), isTrue);
    });

    test('false for a task due tomorrow', () {
      final task = _task(id: 'a', dueDate: _now.add(const Duration(days: 1)));
      expect(isInTodayList(task, now: _now), isFalse);
    });
  });

  group('compareForTodayList / todayTasksFrom', () {
    test('overdue tasks sort before tasks due today', () {
      final overdue = _task(
        id: 'overdue',
        dueDate: _now.subtract(const Duration(days: 1)),
      );
      final dueToday = _task(id: 'today', dueDate: _now);

      final sorted = todayTasksFrom([dueToday, overdue], now: _now);
      expect(sorted.map((t) => t.id), ['overdue', 'today']);
    });

    test('within the same group, higher priority sorts first', () {
      final low = _task(id: 'low', dueDate: _now, priority: TaskPriority.low);
      final high =
          _task(id: 'high', dueDate: _now, priority: TaskPriority.high);
      final medium = _task(id: 'medium', dueDate: _now);

      final sorted = todayTasksFrom([low, medium, high], now: _now);
      expect(sorted.map((t) => t.id), ['high', 'medium', 'low']);
    });

    test('completed tasks always sort after incomplete ones', () {
      final completed = _task(
        id: 'done',
        dueDate: _now.subtract(const Duration(days: 5)), // would be overdue
        completedAt: _now,
      );
      final pending = _task(id: 'pending', dueDate: _now);

      final sorted = todayTasksFrom([completed, pending], now: _now);
      expect(sorted.map((t) => t.id), ['pending', 'done']);
    });

    test('among completed tasks, most recently completed sorts first', () {
      final earlier = _task(
        id: 'earlier',
        dueDate: _now,
        completedAt: _now.subtract(const Duration(hours: 2)),
      );
      final later = _task(
        id: 'later',
        dueDate: _now,
        completedAt: _now.subtract(const Duration(minutes: 5)),
      );

      final sorted = todayTasksFrom([earlier, later], now: _now);
      expect(sorted.map((t) => t.id), ['later', 'earlier']);
    });

    test('todayTasksFrom filters out tasks not in the today list', () {
      final tomorrow =
          _task(id: 'tomorrow', dueDate: _now.add(const Duration(days: 1)));
      final noDueDate = _task(id: 'undated');
      final today = _task(id: 'today', dueDate: _now);

      final sorted = todayTasksFrom([tomorrow, noDueDate, today], now: _now);
      expect(sorted.map((t) => t.id), ['today']);
    });
  });
}
