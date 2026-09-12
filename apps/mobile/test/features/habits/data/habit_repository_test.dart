import 'dart:convert';

// drift also exports isNull/isNotNull, which collide with matcher's.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/habits/data/habit_repository.dart';
import 'package:kunim/features/habits/domain/habit_schedule.dart';
import 'package:kunim/features/habits/domain/local_day.dart';

void main() {
  late AppDatabase db;
  late int localWriteCalls;
  late HabitRepository repo;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    localWriteCalls = 0;
    repo = HabitRepository(db, onLocalWrite: () => localWriteCalls++);
  });

  tearDown(() async {
    await db.close();
  });

  group('createHabit', () {
    test('writes exactly one habits row and one outbox entry, then notifies',
        () async {
      final id = await repo.createHabit(
        title: 'Kunlik Qur\'on',
        schedule: const HabitSchedule.specificWeekdays({1, 2, 3, 4, 5}),
        targetCount: 2,
      );

      final habits = await db.select(db.habits).get();
      expect(habits, hasLength(1));
      expect(habits.single.id, id);
      expect(habits.single.title, 'Kunlik Qur\'on');
      expect(habits.single.targetCount, 2);
      expect(
        HabitSchedule.fromJson(habits.single.frequency).type,
        HabitScheduleType.specificWeekdays,
      );

      final outbox = await db.select(db.syncOutbox).get();
      expect(outbox, hasLength(1));
      expect(outbox.single.entity, 'habits');
      expect(outbox.single.rowId, id);
      expect(outbox.single.op, 'upsert');
      final payload = jsonDecode(outbox.single.payload) as Map<String, dynamic>;
      expect(payload['id'], id);
      expect(payload['title'], 'Kunlik Qur\'on');
      expect(payload['target'], 2);
      expect(payload.containsKey('dirty'), isFalse);

      expect(localWriteCalls, 1);
    });
  });

  group('updateHabit', () {
    test('patches only the given fields, writes one outbox upsert entry',
        () async {
      final id = await repo.createHabit(title: 'Original title');
      localWriteCalls = 0;

      await repo.updateHabit(
        id: id,
        title: const Value('New title'),
        targetCount: const Value(5),
      );

      final row = await repo.findById(id);
      expect(row!.title, 'New title');
      expect(row.targetCount, 5);

      final outbox = await (db.select(
        db.syncOutbox,
      )..where((t) => t.rowId.equals(id)))
          .get();
      // 1 from create + 1 from update.
      expect(outbox, hasLength(2));
      final latest = outbox.reduce((a, b) => a.seq > b.seq ? a : b);
      expect(latest.entity, 'habits');
      expect(latest.op, 'upsert');
      final payload = jsonDecode(latest.payload) as Map<String, dynamic>;
      expect(payload['title'], 'New title');
      expect(payload['target'], 5);

      expect(localWriteCalls, 1);
    });

    test('throws for an unknown habit id and does not notify', () async {
      expect(
        () => repo.updateHabit(id: 'missing', title: const Value('x')),
        throwsStateError,
      );
      expect(localWriteCalls, 0);
    });
  });

  group('archiveHabit', () {
    test('soft-deletes and writes a delete-op outbox entry', () async {
      final id = await repo.createHabit(title: 'To archive');
      localWriteCalls = 0;

      await repo.archiveHabit(id);

      final row = await (db.select(
        db.habits,
      )..where((h) => h.id.equals(id)))
          .getSingle();
      expect(row.deletedAt, isNotNull);

      final outbox = await (db.select(
        db.syncOutbox,
      )..where((t) => t.rowId.equals(id)))
          .get();
      final latest = outbox.reduce((a, b) => a.seq > b.seq ? a : b);
      expect(latest.entity, 'habits');
      expect(latest.op, 'delete');

      expect(localWriteCalls, 1);
    });

    test('archived habits disappear from watchActiveHabits', () async {
      final id = await repo.createHabit(title: 'To archive');
      await repo.archiveHabit(id);

      final active = await repo.watchActiveHabits().first;
      expect(active.where((h) => h.id == id), isEmpty);
    });

    test('is a no-op (no new outbox entry, no notify) when already archived',
        () async {
      final id = await repo.createHabit(title: 'x');
      await repo.archiveHabit(id);
      localWriteCalls = 0;
      final countBefore = (await db.select(db.syncOutbox).get()).length;

      await repo.archiveHabit(id);

      final countAfter = (await db.select(db.syncOutbox).get()).length;
      expect(countAfter, countBefore);
      expect(localWriteCalls, 0);
    });
  });

  group('watchActiveHabitsWithLogOnDay', () {
    test('pairs a habit with its log for the day, or null if none', () async {
      final id = await repo.createHabit(title: 'Water');
      final day = const LocalDay(2026, 9, 12);

      final before = await repo.watchActiveHabitsWithLogOnDay(day).first;
      expect(before.single.habit.id, id);
      expect(before.single.log, isNull);

      await db.into(db.habitLogs).insert(
            HabitLogsCompanion.insert(
              habitId: id,
              date: day.toUtcMidnight(),
              count: const Value(3),
            ),
          );

      final after = await repo.watchActiveHabitsWithLogOnDay(day).first;
      expect(after.single.log?.count, 3);
    });
  });
}
