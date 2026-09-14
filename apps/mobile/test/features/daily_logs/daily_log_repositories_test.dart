// The four daily log repositories: one live row per day, every write queued
// with its full snake_case wire row, soft deletes, and the same bounds the
// server validates.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/family/data/family_log_repository.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/health/data/health_log_repository.dart';
import 'package:kunim/features/mood/data/mood_log_repository.dart';
import 'package:kunim/features/sleep/data/sleep_log_repository.dart';

const _day = LocalDay(2026, 9, 12);
DateTime _clock() => DateTime.utc(2026, 9, 12, 8, 15);

void main() {
  late AppDatabase db;
  var localWrites = 0;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    localWrites = 0;
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<SyncOutboxData>> outboxFor(String entity) =>
      (db.select(db.syncOutbox)..where((e) => e.entity.equals(entity))).get();

  Map<String, dynamic> payloadOf(SyncOutboxData entry) =>
      jsonDecode(entry.payload) as Map<String, dynamic>;

  group('mood', () {
    MoodLogRepository repo() =>
        MoodLogRepository(db, onLocalWrite: () => localWrites++, now: _clock);

    test('saving twice on one day edits the same row', () async {
      final first =
          await repo().saveForDay(_day, score: 3, tags: ['sad', 'calm']);
      final second = await repo()
          .saveForDay(_day, score: 5, tags: ['grateful'], note: '  shukr  ');

      expect(second.id, first.id);
      final live = await repo().watchForDay(_day).first;
      expect(live?.score, 5);
      expect(MoodLogRepository.tagsOf(live!), ['grateful']);
      expect(live.note, 'shukr');
      expect(localWrites, 2);

      final outbox = await outboxFor(MoodLogRepository.entityName);
      expect(outbox, hasLength(2));
      // Tags are stored in the screen's order, not the tap order.
      expect(payloadOf(outbox.first)['tags'], ['calm', 'sad']);
      final wire = payloadOf(outbox.last);
      expect(wire['date'], '2026-09-12');
      expect(wire['score'], 5);
      expect(wire['ref_id'], isNull);
      expect(wire.containsKey('dirty'), isFalse);
    });

    test('deleting tombstones the row and queues a delete', () async {
      await repo().saveForDay(_day, score: 4);
      await repo().deleteForDay(_day);

      expect(await repo().watchForDay(_day).first, isNull);
      final last = (await outboxFor(MoodLogRepository.entityName)).last;
      expect(last.op, 'delete');
      expect(payloadOf(last)['deleted_at'], isNotNull);
    });

    test('rejects out-of-range scores and malformed tags, keeps unknown ones',
        () async {
      expect(() => repo().saveForDay(_day, score: 0), throwsArgumentError);
      expect(() => repo().saveForDay(_day, score: 6), throwsArgumentError);
      expect(
        () => repo().saveForDay(_day, score: 3, tags: ['Not a code']),
        throwsArgumentError,
      );

      final saved = await repo()
          .saveForDay(_day, score: 3, tags: ['new_feeling', 'calm']);
      expect(MoodLogRepository.tagsOf(saved), ['calm', 'new_feeling']);
    });
  });

  test('a code list may hold up to 32 entries, as the server allows', () async {
    final repo = MoodLogRepository(db, onLocalWrite: () {}, now: _clock);
    final codes = [for (var i = 0; i < 32; i++) 'feeling_$i'];

    final saved = await repo.saveForDay(_day, score: 3, tags: codes);
    expect(MoodLogRepository.tagsOf(saved), hasLength(32));
    expect(
      () => repo.saveForDay(_day, score: 3, tags: [...codes, 'one_more']),
      throwsArgumentError,
    );
  });

  group('sleep', () {
    SleepLogRepository repo() =>
        SleepLogRepository(db, onLocalWrite: () => localWrites++, now: _clock);

    test('derives the duration from whole-minute bed and wake times', () async {
      final saved = await repo().saveForDay(
        _day,
        bedTime: DateTime.utc(2026, 9, 11, 18, 10, 42),
        wakeTime: DateTime.utc(2026, 9, 12, 1, 40, 5),
        quality: 4,
      );

      expect(saved.durationMin, 450);
      final wire = payloadOf((await outboxFor('sleep_logs')).single);
      expect(wire['bed_time'], '2026-09-11T18:10:00.000Z');
      expect(wire['wake_time'], '2026-09-12T01:40:00.000Z');
      expect(wire['duration_min'], 450);
      expect(wire['quality'], 4);
      expect(wire['date'], '2026-09-12');
    });

    test('rejects impossible nights and ratings', () {
      final wake = DateTime.utc(2026, 9, 12, 1);
      expect(
        () => repo().saveForDay(_day, bedTime: wake, wakeTime: wake),
        throwsArgumentError,
      );
      expect(
        () => repo().saveForDay(
          _day,
          bedTime: wake.subtract(const Duration(hours: 25)),
          wakeTime: wake,
        ),
        throwsArgumentError,
      );
      expect(
        () => repo().saveForDay(
          _day,
          bedTime: wake.subtract(const Duration(hours: 7)),
          wakeTime: wake,
          quality: 6,
        ),
        throwsArgumentError,
      );
    });
  });

  group('health', () {
    HealthLogRepository repo() =>
        HealthLogRepository(db, onLocalWrite: () => localWrites++, now: _clock);

    test('stores only the values given', () async {
      await repo().saveForDay(_day, waterMl: 500, weightKg: 70.25);

      final wire = payloadOf((await outboxFor('health_logs')).single);
      expect(wire['water_ml'], 500);
      expect(wire['weight_kg'], 70.25);
      expect(wire['steps'], isNull);
      expect(wire['calories'], isNull);
    });

    test('needs a value and keeps every value in range', () {
      expect(() => repo().saveForDay(_day), throwsArgumentError);
      expect(() => repo().saveForDay(_day, steps: -1), throwsArgumentError);
      expect(() => repo().saveForDay(_day, weightKg: 5), throwsArgumentError);
      expect(
        () => repo().saveForDay(_day, waterMl: 20001),
        throwsArgumentError,
      );
    });
  });

  group('family', () {
    FamilyLogRepository repo() =>
        FamilyLogRepository(db, onLocalWrite: () => localWrites++, now: _clock);

    test('stores minutes and activities in display order', () async {
      final saved = await repo()
          .saveForDay(_day, minutes: 45, activities: ['walk', 'meal']);

      expect(FamilyLogRepository.activitiesOf(saved), ['meal', 'walk']);
      final wire = payloadOf((await outboxFor('family_logs')).single);
      expect(wire['minutes'], 45);
      expect(wire['activities'], ['meal', 'walk']);
    });

    test('needs minutes, an activity or a note', () {
      expect(() => repo().saveForDay(_day), throwsArgumentError);
      expect(() => repo().saveForDay(_day, minutes: 2000), throwsArgumentError);
    });
  });
}
