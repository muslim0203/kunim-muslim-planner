// Pulled rows arrive in the SERVER's wire shape, which is not the local
// column shape: DATE fields are bare dates, some fields are renamed or
// JSON-typed, and enums are names. These tests seed exactly what the real
// server sends and check that the local rows are usable afterwards — the
// existing pull tests only ever seeded `tasks` rows already in local shape.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/db/tables/tasks_table.dart' show TaskPriority;
import 'package:kunim/core/sync/outbox.dart';
import 'package:kunim/core/sync/sync_engine.dart';
import 'package:kunim/features/family/data/family_log_repository.dart';
import 'package:kunim/features/habits/data/habit_log_repository.dart';
import 'package:kunim/features/habits/domain/habit_schedule.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/health/data/health_log_repository.dart';
import 'package:kunim/features/mood/data/mood_log_repository.dart';
import 'package:kunim/features/sleep/data/sleep_log_repository.dart';

import 'sync_engine_fake_server.dart';

const _day = LocalDay(2026, 9, 12);

Map<String, dynamic> _base(String id, {String? deletedAt}) => {
      'id': id,
      'user_id': null,
      'created_at': '2026-09-12T08:00:00.000Z',
      'updated_at': '2026-09-12T08:00:00.000Z',
      'deleted_at': deletedAt,
      'server_version': 0,
    };

void main() {
  late AppDatabase db;
  late FakeSyncServer server;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    server = FakeSyncServer();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pull() async {
    final engine = SyncEngine(
      db: db,
      api: server,
      outboxDao: OutboxDao(db),
      stateStore: SyncStateStore(db),
    );
    expect(await engine.syncOnce(), isA<SyncSuccess>());
  }

  test('phase-2 rows: dates, renamed fields and enum names', () async {
    server
      ..seedServerRow('tasks', {
        ..._base('t-1'),
        'title': 'Hisobot',
        'description': null,
        'category_id': null,
        'priority': 'high',
        'due_date': '2026-09-12',
        'completed_at': null,
      })
      ..seedServerRow('habits', {
        ..._base('h-1'),
        'title': 'Erta turish',
        'description': null,
        'schedule': {
          'type': 'specific_weekdays',
          'weekdays': [1, 3],
        },
        'target': 2,
        'color': null,
        'reminder_minutes': 450,
      })
      ..seedServerRow('habit_logs', {
        ..._base('hl-1'),
        'habit_id': 'h-1',
        'date': '2026-09-12',
        'count': 3,
        'value': null,
        'note': null,
      })
      ..seedServerRow('goals', {
        ..._base('g-1'),
        'title': 'Maqsad',
        'description': null,
        'target_date': '2026-12-31',
        'progress_percent': 40,
      });

    await pull();

    final task = await (db.select(db.tasks)..where((t) => t.id.equals('t-1')))
        .getSingle();
    expect(task.priority, TaskPriority.high);
    expect(task.dueDate, DateTime.utc(2026, 9, 12));
    expect(task.dueDate!.isUtc, isTrue);

    final habit = await (db.select(db.habits)..where((h) => h.id.equals('h-1')))
        .getSingle();
    expect(
      HabitSchedule.fromJson(habit.frequency).toJson(),
      const HabitSchedule.specificWeekdays({1, 3}).toJson(),
    );
    expect(habit.targetCount, 2);
    // 07:30 on the wire is 07:30 in the local column, minutes and all.
    expect(habit.reminderMinutes, 450);

    // The pulled log must be found by the same day query a local write uses.
    final log = await HabitLogRepository(db, onLocalWrite: () {})
        .watchLogForDay(habitId: 'h-1', day: _day)
        .first;
    expect(log?.count, 3);

    final goal = await (db.select(db.goals)..where((g) => g.id.equals('g-1')))
        .getSingle();
    expect(goal.targetDate, DateTime.utc(2026, 12, 31));
  });

  test('daily log rows: lists, dates and a rule-14 tombstone', () async {
    server
      ..seedServerRow('mood_logs', {
        ..._base('m-1'),
        'ref_id': null,
        'date': '2026-09-12',
        'score': 4,
        'tags': ['calm', 'grateful'],
        'note': 'xotirjam',
      })
      // The losing row of a natural-key collision: same day, tombstoned,
      // with the server's `merged_into` marker the client does not store.
      ..seedServerRow('mood_logs', {
        ..._base('m-2', deletedAt: '2026-09-12T08:05:00.000Z'),
        'ref_id': null,
        'date': '2026-09-12',
        'score': 2,
        'tags': <String>[],
        'note': null,
        'merged_into': 'm-1',
      })
      ..seedServerRow('sleep_logs', {
        ..._base('s-1'),
        'ref_id': null,
        'date': '2026-09-12',
        'bed_time': '2026-09-11T18:00:00.000Z',
        'wake_time': '2026-09-12T01:30:00.000Z',
        'duration_min': 450,
        'quality': 4,
        'note': null,
      })
      ..seedServerRow('health_logs', {
        ..._base('he-1'),
        'ref_id': null,
        'date': '2026-09-12',
        'water_ml': 1500,
        'steps': 8000,
        'workout_min': 30,
        'calories': null,
        'weight_kg': 72.5,
        'note': null,
      })
      ..seedServerRow('family_logs', {
        ..._base('f-1'),
        'ref_id': null,
        'date': '2026-09-12',
        'minutes': 90,
        'activities': ['meal', 'walk'],
        'note': null,
      });

    await pull();

    final mood = await MoodLogRepository(db, onLocalWrite: () {})
        .watchForDay(_day)
        .first;
    expect(mood?.id, 'm-1');
    expect(mood?.score, 4);
    expect(MoodLogRepository.tagsOf(mood!), ['calm', 'grateful']);

    final sleep = await SleepLogRepository(db, onLocalWrite: () {})
        .watchForDay(_day)
        .first;
    expect(sleep?.durationMin, 450);
    expect(sleep?.bedTime, DateTime.utc(2026, 9, 11, 18));

    final health = await HealthLogRepository(db, onLocalWrite: () {})
        .watchForDay(_day)
        .first;
    expect(health?.steps, 8000);
    expect(health?.weightKg, 72.5);

    final family = await FamilyLogRepository(db, onLocalWrite: () {})
        .watchForDay(_day)
        .first;
    expect(family?.minutes, 90);
    expect(FamilyLogRepository.activitiesOf(family!), ['meal', 'walk']);
  });
}
