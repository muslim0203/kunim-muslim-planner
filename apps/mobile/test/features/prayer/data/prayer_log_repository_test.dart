// Prayer marks: one live row per prayer per day, raising a mark updates the
// row, lowering or clearing one tombstones it, and every write is queued with
// its snake_case wire row.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/prayer/data/prayer_log_repository.dart';
import 'package:kunim/features/prayer/domain/prayer_log_status.dart';

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

  PrayerLogRepository repo() =>
      PrayerLogRepository(db, onLocalWrite: () => localWrites++, now: _clock);

  Future<List<PrayerLog>> allRows() => db.select(db.prayerLogs).get();

  Future<List<Map<String, dynamic>>> queued() async {
    final entries = await (db.select(db.syncOutbox)
          ..where((e) => e.entity.equals(PrayerLogRepository.entityName))
          ..orderBy([(e) => OrderingTerm.asc(e.seq)]))
        .get();
    return [
      for (final entry in entries)
        jsonDecode(entry.payload) as Map<String, dynamic>,
    ];
  }

  test('marking a prayer queues its wire row', () async {
    await repo().mark(_day, 'fajr', PrayerLogStatus.alone);

    expect(await repo().watchDay(_day).first, {'fajr': PrayerLogStatus.alone});
    final wire = (await queued()).single;
    expect(wire['ref_id'], 'fajr');
    expect(wire['date'], '2026-09-12');
    expect(wire['status'], 'alone');
    expect(wire['note'], isNull);
    expect(wire.containsKey('dirty'), isFalse);
    expect(localWrites, 1);
  });

  test('raising a mark updates the same row', () async {
    final first = await repo().mark(_day, 'asr', PrayerLogStatus.qaza);
    final second = await repo().mark(_day, 'asr', PrayerLogStatus.jamaah);

    expect(second.id, first.id);
    expect((await allRows()).single.status, 'jamaah');
    expect(await queued(), hasLength(2));
  });

  test('lowering a mark replaces the row, so sync cannot raise it back',
      () async {
    final first = await repo().mark(_day, 'isha', PrayerLogStatus.jamaah);
    final second = await repo().mark(_day, 'isha', PrayerLogStatus.qaza);

    expect(second.id, isNot(first.id));
    final rows = await allRows();
    expect(rows.firstWhere((r) => r.id == first.id).deletedAt, isNotNull);
    expect(await repo().watchDay(_day).first, {'isha': PrayerLogStatus.qaza});
    expect(
      [
        for (final wire in await queued())
          (wire['id'], wire['deleted_at'] != null)
      ],
      [(first.id, false), (first.id, true), (second.id, false)],
    );
  });

  test('marking the same status again writes nothing', () async {
    await repo().mark(_day, 'dhuhr', PrayerLogStatus.alone);
    await repo().mark(_day, 'dhuhr', PrayerLogStatus.alone);

    expect(await queued(), hasLength(1));
    expect(localWrites, 1);
  });

  test('clearing tombstones the mark and queues a delete', () async {
    await repo().mark(_day, 'maghrib', PrayerLogStatus.jamaah);
    await repo().clear(_day, 'maghrib');

    expect(await repo().watchDay(_day).first, isEmpty);
    expect((await queued()).last['deleted_at'], isNotNull);
  });

  test('sunrise and unknown keys cannot be marked', () async {
    await expectLater(
      repo().mark(_day, 'sunrise', PrayerLogStatus.alone),
      throwsArgumentError,
    );
    expect(await allRows(), isEmpty);
  });
}
