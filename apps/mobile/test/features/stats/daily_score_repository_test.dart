// Today's score row: one live row per day, an identical save writes nothing,
// and every write is queued with its snake_case wire row.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/stats/data/daily_score_repository.dart';

const _day = LocalDay(2026, 9, 18);
DateTime _clock() => DateTime.utc(2026, 9, 18, 20, 30);

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

  DailyScoreRepository repo() =>
      DailyScoreRepository(db, onLocalWrite: () => localWrites++, now: _clock);

  Future<List<Map<String, dynamic>>> queued() async {
    final entries = await (db.select(db.syncOutbox)
          ..where((e) => e.entity.equals(DailyScoreRepository.entityName))
          ..orderBy([(e) => OrderingTerm.asc(e.seq)]))
        .get();
    return [
      for (final entry in entries)
        jsonDecode(entry.payload) as Map<String, dynamic>,
    ];
  }

  test('the first score of a day is queued as a wire row', () async {
    await repo().saveForDay(_day, points: 35, done: 1, planned: 1);

    final wire = (await queued()).single;
    expect(wire['date'], '2026-09-18');
    expect(wire['points'], 35);
    expect(wire['done'], 1);
    expect(wire['planned'], 1);
    expect(wire.containsKey('dirty'), isFalse);
    expect(localWrites, 1);
  });

  test('a changed score updates the same row', () async {
    final first =
        await repo().saveForDay(_day, points: 10, done: 1, planned: 2);
    final second =
        await repo().saveForDay(_day, points: 45, done: 2, planned: 2);

    expect(second!.id, first!.id);
    expect((await db.select(db.dailyScores).get()).single.points, 45);
    expect(await queued(), hasLength(2));
  });

  test('saving the same score again writes nothing', () async {
    await repo().saveForDay(_day, points: 35, done: 1, planned: 1);
    await repo().saveForDay(_day, points: 35, done: 1, planned: 1);

    expect(await queued(), hasLength(1));
    expect(localWrites, 1);
  });

  test('each day keeps its own row', () async {
    await repo().saveForDay(_day, points: 35, done: 1, planned: 1);
    await repo().saveForDay(_day.addDays(-1), points: 10, done: 1, planned: 2);

    expect(await db.select(db.dailyScores).get(), hasLength(2));
    expect((await repo().findForDay(_day))?.points, 35);
  });
}
