// Round-trip tests for the phase-2 sync tables (ADR-0002 §1 / `docs/plan.md`
// §3): every syncable table must preserve the mandatory sync columns
// (`id`, `userId`, `createdAt`, `updatedAt`, `deletedAt`, `serverVersion`,
// `dirty`) exactly as written, and `dirty` defaults to `true` for a fresh
// local write (nothing has been pushed yet).
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/db/tables/tasks_table.dart';

AppDatabase _openInMemory() =>
    AppDatabase.withExecutor(NativeDatabase.memory());

void main() {
  late AppDatabase db;

  setUp(() {
    db = _openInMemory();
  });

  tearDown(() async {
    await db.close();
  });

  DateTime utc(int y, int m, int d, [int h = 0, int min = 0, int s = 0]) =>
      DateTime.utc(y, m, d, h, min, s);

  group('Tasks', () {
    test('round-trips the mandatory sync columns and feature fields', () async {
      final createdAt = utc(2026, 9, 1, 8);
      final updatedAt = utc(2026, 9, 1, 9);

      await db.into(db.tasks).insert(
            TasksCompanion.insert(
              id: const Value('11111111-1111-4111-8111-111111111111'),
              userId: const Value('user-1'),
              createdAt: Value(createdAt),
              updatedAt: Value(updatedAt),
              title: 'Namoz vaqtida turish',
              priority: const Value(TaskPriority.high),
              dueDate: Value(utc(2026, 9, 2)),
            ),
          );

      final row = await db.select(db.tasks).getSingle();

      expect(row.id, '11111111-1111-4111-8111-111111111111');
      expect(row.userId, 'user-1');
      expect(row.createdAt, createdAt);
      expect(row.updatedAt, updatedAt);
      expect(row.deletedAt, isNull);
      expect(row.serverVersion, 0);
      expect(row.dirty, isTrue, reason: 'local writes must default dirty=1');
      expect(row.title, 'Namoz vaqtida turish');
      expect(row.priority, TaskPriority.high);
      expect(row.dueDate, utc(2026, 9, 2));
      expect(row.completedAt, isNull);
    });

    test('completedAt is the only "done" signal — no separate flag exists',
        () async {
      await db.into(db.tasks).insert(
            TasksCompanion.insert(title: 'Xatm qilish'),
          );
      final inserted = await db.select(db.tasks).getSingle();

      await (db.update(db.tasks)..where((t) => t.id.equals(inserted.id))).write(
        TasksCompanion(
          completedAt: Value(utc(2026, 9, 3)),
          updatedAt: Value(utc(2026, 9, 3)),
        ),
      );

      final completed = await db.select(db.tasks).getSingle();
      expect(completed.completedAt, utc(2026, 9, 3));
    });
  });

  group('TaskCategories', () {
    test('round-trips', () async {
      await db.into(db.taskCategories).insert(
            TaskCategoriesCompanion.insert(
                name: 'Ibodat', sortOrder: const Value(2)),
          );
      final row = await db.select(db.taskCategories).getSingle();
      expect(row.name, 'Ibodat');
      expect(row.sortOrder, 2);
      expect(row.dirty, isTrue);
      expect(row.serverVersion, 0);
    });
  });

  group('CalendarEvents', () {
    test('round-trips including RRULE', () async {
      await db.into(db.calendarEvents).insert(
            CalendarEventsCompanion.insert(
              title: 'Jamoat namozi',
              startAt: utc(2026, 9, 4, 12),
              rrule: const Value('FREQ=WEEKLY;BYDAY=FR'),
            ),
          );
      final row = await db.select(db.calendarEvents).getSingle();
      expect(row.rrule, 'FREQ=WEEKLY;BYDAY=FR');
      expect(row.allDay, isFalse);
      expect(row.dirty, isTrue);
    });
  });

  group('Habits and HabitLogs', () {
    test('habit_logs enforces the (userId, habitId, date) natural key',
        () async {
      await db.into(db.habits).insert(
            HabitsCompanion.insert(title: 'Kunlik Qur\'on'),
          );
      final habit = await db.select(db.habits).getSingle();

      await db.into(db.habitLogs).insert(
            HabitLogsCompanion.insert(
              userId: const Value('user-1'),
              habitId: habit.id,
              date: utc(2026, 9, 5),
              count: const Value(2),
            ),
          );

      final log = await db.select(db.habitLogs).getSingle();
      expect(log.habitId, habit.id);
      expect(log.count, 2);

      // A second live row for the SAME (userId, habitId, date) must be
      // rejected by the unique constraint (ADR-0002 conflict-matrix rule 9).
      await expectLater(
        db.into(db.habitLogs).insert(
              HabitLogsCompanion.insert(
                userId: const Value('user-1'),
                habitId: habit.id,
                date: utc(2026, 9, 5),
                count: const Value(5),
              ),
            ),
        throwsA(anything),
      );
    });
  });

  group('Goals and Milestones', () {
    test('round-trip', () async {
      await db.into(db.goals).insert(
            GoalsCompanion.insert(
              title: 'Yiliga bir marta xatm',
              progressPercent: const Value(40),
            ),
          );
      final goal = await db.select(db.goals).getSingle();

      await db.into(db.milestones).insert(
            MilestonesCompanion.insert(goalId: goal.id, title: '10-juz'),
          );
      final milestone = await db.select(db.milestones).getSingle();

      expect(goal.progressPercent, 40);
      expect(milestone.goalId, goal.id);
      expect(milestone.completedAt, isNull);
    });
  });
}
