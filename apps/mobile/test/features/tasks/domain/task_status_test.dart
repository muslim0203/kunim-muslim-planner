// Pure-Dart unit tests for `features/tasks/domain/task_status.dart` — no
// database needed, `Task` is a plain Drift data class.
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/db/tables/tasks_table.dart';
import 'package:kunim/features/tasks/domain/task_status.dart';

Task _task({
  DateTime? dueDate,
  DateTime? completedAt,
  DateTime? deletedAt,
}) {
  final now = DateTime.utc(2026, 9, 12, 8);
  return Task(
    id: 't1',
    createdAt: now,
    updatedAt: now,
    deletedAt: deletedAt,
    serverVersion: 0,
    dirty: true,
    title: 'Test task',
    priority: TaskPriority.medium,
    dueDate: dueDate,
    completedAt: completedAt,
  );
}

void main() {
  group('isCompleted', () {
    test('is derived from completedAt, never a separate flag', () {
      expect(_task(completedAt: null).isCompleted, isFalse);
      expect(
        _task(completedAt: DateTime.utc(2026, 9, 12)).isCompleted,
        isTrue,
      );
    });
  });

  group('isOverdue', () {
    final now = DateTime.utc(2026, 9, 12, 12);

    test('no due date is never overdue', () {
      expect(_task().isOverdue(now: now), isFalse);
    });

    test('a due date in the past and not completed is overdue', () {
      final task = _task(dueDate: now.subtract(const Duration(hours: 1)));
      expect(task.isOverdue(now: now), isTrue);
    });

    test('a due date in the future is not overdue', () {
      final task = _task(dueDate: now.add(const Duration(hours: 1)));
      expect(task.isOverdue(now: now), isFalse);
    });

    test('a completed task is never overdue, even past its due date', () {
      final task = _task(
        dueDate: now.subtract(const Duration(days: 1)),
        completedAt: now,
      );
      expect(task.isOverdue(now: now), isFalse);
    });
  });

  group('isDeleted', () {
    test('true only when deletedAt is set', () {
      expect(_task().isDeleted, isFalse);
      expect(_task(deletedAt: DateTime.utc(2026, 9, 1)).isDeleted, isTrue);
    });
  });
}
