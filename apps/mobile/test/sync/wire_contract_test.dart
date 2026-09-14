// The cross-stack half of the wire contract.
//
// Every repository builds its own `sync_outbox` payload by hand, and the
// server's row schemas are `extra="forbid"` snake_case. Nothing used to check
// the two against each other: the Dart tests asserted against a Dart
// `FakeSyncServer` and the Python tests against Python clients, so all seven
// Phase-2 entities were rejected as `schema_invalid` by the real server while
// both suites stayed green.
//
// This test captures the payload each repository ACTUALLY enqueues, normalises
// the volatile parts (ids, timestamps) and writes it to
// `packages/kunim_contracts/golden/<entity>.json`.
// `apps/api/tests/test_wire_contract.py` then validates those same files
// against the Pydantic schema the server really uses. Change one side without
// the other and one of the two tests fails.
//
// Regenerate after an intentional schema change:
//   flutter test test/sync/wire_contract_test.dart --dart-define=UPDATE_GOLDEN=true
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/db/tables/tasks_table.dart' show TaskPriority;
import 'package:kunim/features/calendar/data/calendar_event_repository.dart';
import 'package:kunim/features/family/data/family_log_repository.dart';
import 'package:kunim/features/goals/data/goal_repository.dart';
import 'package:kunim/features/goals/data/milestone_repository.dart';
import 'package:kunim/features/habits/data/habit_log_repository.dart';
import 'package:kunim/features/habits/data/habit_repository.dart';
import 'package:kunim/features/habits/domain/habit_schedule.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/health/data/health_log_repository.dart';
import 'package:kunim/features/mood/data/mood_log_repository.dart';
import 'package:kunim/features/sleep/data/sleep_log_repository.dart';
import 'package:kunim/features/tasks/data/task_category_repository.dart';
import 'package:kunim/features/tasks/data/task_repository.dart';

const _updateGolden =
    bool.fromEnvironment('UPDATE_GOLDEN', defaultValue: false);

/// Directory the golden payloads live in, relative to `apps/mobile`.
final _goldenDir = Directory('../../packages/kunim_contracts/golden').absolute;

// Fixed stand-ins so a golden file is stable across runs.
const _fixedId = '00000000-0000-4000-8000-000000000001';
const _fixedTimestamp = '2026-09-12T08:15:30.123Z';
const _fixedDate = '2026-09-12';

/// Fields whose values only make sense together and are already fixed by the
/// test clock: normalising `sleep_logs`' bed and wake times to the same
/// instant would make the golden a zero-length night the server rightly
/// rejects.
const _keepAsIs = {'bed_time', 'wake_time'};

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _timestampPattern =
    RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');
final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Replaces ids and instants with fixed values, keeping their *format*.
///
/// The contract is the set of field names and the shape of their values, not
/// the particular uuid or millisecond a test happened to produce.
Object? _normalise(Object? value) {
  if (value is String) {
    if (_uuidPattern.hasMatch(value)) return _fixedId;
    if (_timestampPattern.hasMatch(value)) return _fixedTimestamp;
    if (_datePattern.hasMatch(value)) return _fixedDate;
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key as String: _keepAsIs.contains(entry.key)
            ? entry.value
            : _normalise(entry.value),
    };
  }
  if (value is List) return value.map(_normalise).toList();
  return value;
}

Future<Map<String, dynamic>> _capture(
  AppDatabase db,
  String entity,
  Future<void> Function() action,
) async {
  await db.delete(db.syncOutbox).go();
  await action();
  final entries = await (db.select(db.syncOutbox)
        ..where((e) => e.entity.equals(entity)))
      .get();
  expect(entries, isNotEmpty,
      reason: '$entity: the repository enqueued no outbox entry');
  final decoded = jsonDecode(entries.last.payload) as Map<String, dynamic>;
  return _normalise(decoded)! as Map<String, dynamic>;
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('every repository payload is captured as a golden wire row', () async {
    const userId = '00000000-0000-4000-8000-0000000000ff';
    final at = DateTime.utc(2026, 9, 12, 8, 15, 30, 123);
    DateTime nowFn() => at;
    final day = LocalDay(at.year, at.month, at.day);

    final payloads = <String, Map<String, dynamic>>{};

    // --- tasks ------------------------------------------------------------
    final tasks = TaskRepository(db, onLocalWrite: () {});
    payloads['tasks'] = await _capture(db, 'tasks', () async {
      await tasks.createTask(
        title: 'Qur\'on tilovati',
        description: 'kamida 1 sahifa',
        priority: TaskPriority.high,
        dueDate: at,
        userId: userId,
      );
    });

    // --- task_categories --------------------------------------------------
    final categories = TaskCategoryRepository(db, onLocalWrite: () {});
    payloads['task_categories'] =
        await _capture(db, 'task_categories', () async {
      await categories.createCategory(
        name: 'Ibodat',
        color: '#2E7D32',
        sortOrder: 1,
        userId: userId,
      );
    });

    // --- habits -----------------------------------------------------------
    final habits = HabitRepository(db, onLocalWrite: () {});
    final habitId = await habits.createHabit(
      title: 'Erta turish',
      description: 'bomdodga qadar',
      schedule: const HabitSchedule.specificWeekdays({1, 2, 3, 4, 5}),
      targetCount: 1,
      color: '#1565C0',
      userId: userId,
    );
    // Re-capture through the update path so the golden covers `_payloadOf`
    // (create builds its payload inline).
    payloads['habits'] = await _capture(db, 'habits', () async {
      await habits.updateHabit(id: habitId, title: const Value('Erta turish'));
    });

    // --- habit_logs -------------------------------------------------------
    final logs = HabitLogRepository(db, onLocalWrite: () {});
    payloads['habit_logs'] = await _capture(db, 'habit_logs', () async {
      await logs.logCompletion(
        habitId: habitId,
        day: day,
        userId: userId,
      );
    });

    // --- goals ------------------------------------------------------------
    final goals = GoalRepository(db, onLocalWrite: () {}, now: nowFn);
    final goal = await goals.createGoal(
      title: 'Ingliz tilini yaxshilash',
      description: '3 oylik maqsad',
      targetDate: at,
      progressPercent: 10,
      userId: userId,
    );
    payloads['goals'] = await _capture(db, 'goals', () async {
      await goals.createGoal(
        title: 'Ingliz tilini yaxshilash',
        description: '3 oylik maqsad',
        targetDate: at,
        progressPercent: 10,
        userId: userId,
      );
    });

    // --- milestones -------------------------------------------------------
    final milestones = MilestoneRepository(db, onLocalWrite: () {}, now: nowFn);
    payloads['milestones'] = await _capture(db, 'milestones', () async {
      await milestones.createMilestone(
        goalId: goal.id,
        title: '12 ta bosqichdan biri',
        targetDate: at,
        sortOrder: 2,
        progressPercent: 25,
        userId: userId,
      );
    });

    // --- calendar_events --------------------------------------------------
    final events = CalendarEventRepository(db, onLocalWrite: () {}, now: nowFn);
    payloads['calendar_events'] =
        await _capture(db, 'calendar_events', () async {
      await events.createEvent(
        title: 'Jamoa uchrashuvi',
        description: 'haftalik',
        startAt: at,
        endAt: at.add(const Duration(hours: 1)),
        allDay: false,
        rrule: 'FREQ=WEEKLY;BYDAY=MO,WE',
        location: 'Toshkent',
        userId: userId,
      );
    });

    // --- mood_logs --------------------------------------------------------
    final mood = MoodLogRepository(db, onLocalWrite: () {}, now: nowFn);
    payloads['mood_logs'] = await _capture(db, 'mood_logs', () async {
      await mood.saveForDay(
        day,
        score: 4,
        tags: const ['calm', 'grateful'],
        note: 'Bugun xotirjam kun',
        userId: userId,
      );
    });

    // --- sleep_logs -------------------------------------------------------
    final sleep = SleepLogRepository(db, onLocalWrite: () {}, now: nowFn);
    payloads['sleep_logs'] = await _capture(db, 'sleep_logs', () async {
      await sleep.saveForDay(
        day,
        bedTime: at.subtract(const Duration(hours: 7, minutes: 30)),
        wakeTime: at,
        quality: 4,
        note: 'Yaxshi uxladim',
        userId: userId,
      );
    });

    // --- health_logs ------------------------------------------------------
    final health = HealthLogRepository(db, onLocalWrite: () {}, now: nowFn);
    payloads['health_logs'] = await _capture(db, 'health_logs', () async {
      await health.saveForDay(
        day,
        waterMl: 1500,
        steps: 8000,
        workoutMin: 30,
        calories: 2100,
        weightKg: 72.5,
        note: 'Kechki sayr',
        userId: userId,
      );
    });

    // --- family_logs ------------------------------------------------------
    final family = FamilyLogRepository(db, onLocalWrite: () {}, now: nowFn);
    payloads['family_logs'] = await _capture(db, 'family_logs', () async {
      await family.saveForDay(
        day,
        minutes: 90,
        activities: const ['meal', 'walk'],
        note: 'Oila bilan kechki ovqat',
        userId: userId,
      );
    });

    // --- compare or regenerate -------------------------------------------
    final encoder = const JsonEncoder.withIndent('  ');
    for (final entry in payloads.entries) {
      final file = File('${_goldenDir.path}/${entry.key}.json');
      final rendered = '${encoder.convert(entry.value)}\n';

      if (_updateGolden) {
        await file.parent.create(recursive: true);
        await file.writeAsString(rendered);
        continue;
      }

      expect(file.existsSync(), isTrue,
          reason: 'missing golden ${file.path}. Regenerate with '
              '--dart-define=UPDATE_GOLDEN=true');
      expect(
        jsonDecode(await file.readAsString()),
        entry.value,
        reason: '${entry.key}: the payload this repository enqueues no longer '
            'matches its golden wire row. If the change is intentional, '
            'regenerate with --dart-define=UPDATE_GOLDEN=true AND make sure '
            'apps/api/tests/test_wire_contract.py still passes.',
      );
    }
  });
}
