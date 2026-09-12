// The push loop must always terminate.
//
// `_pushAll` used to exit only when a batch came back SHORTER than the
// server-reported limit. But `schema_invalid` / `payload_too_large` entries
// are deliberately left in the outbox (ADR-0002 §3: diagnose, never
// blind-retry), so a full batch of permanently-failing rows made `nextBatch`
// return the same `maxChangesPerBatch` entries for ever: an unbounded push
// storm against the server that also starved every healthy row queued behind
// them.
//
// A whole batch of unsendable rows is not hypothetical -- it is exactly what
// happened while the client payload builders disagreed with the server's row
// schemas, and what a transient server error still produces today (the API
// answers `schema_invalid` for any unhandled exception).
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/outbox.dart';
import 'package:kunim/core/sync/sync_engine.dart';

import 'sync_engine_fake_server.dart';
import 'sync_engine_test_helpers.dart';

/// Queues an outbox entry whose payload has no `updated_at`, which
/// [FakeSyncServer] (like the real API) answers with `schema_invalid` -- a
/// terminal rejection that stays in the outbox.
Future<void> _enqueueUnsendable(AppDatabase db, String rowId) async {
  await db.into(db.syncOutbox).insert(
        SyncOutboxCompanion.insert(
          entity: 'tasks',
          rowId: rowId,
          op: 'upsert',
          // No `updated_at` on purpose.
          payload: jsonEncode({'id': rowId, 'title': 'unsendable $rowId'}),
        ),
      );
}

void main() {
  late AppDatabase db;
  late FakeSyncServer server;
  late SyncEngine engine;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    // A small cap so "a full batch of failures" needs only a few rows.
    server = FakeSyncServer(maxChangesPerBatch: 3);
    engine = SyncEngine(
      db: db,
      api: server,
      outboxDao: OutboxDao(db),
      stateStore: SyncStateStore(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('a full batch of terminally rejected entries ends the push cycle',
      () async {
    // More than one full batch, so the old code would keep looping.
    for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) {
      await _enqueueUnsendable(db, id);
    }
    expect(await readOutbox(db), hasLength(6));

    // The real assertion is that this returns at all.
    final status = await engine.syncOnce();

    expect(status, isA<SyncSuccess>(),
        reason: 'a quarantined outbox is not a transport failure');
    expect(server.pushCallCount, lessThanOrEqualTo(2),
        reason: 'the cycle must stop as soon as an iteration makes no '
            'progress, not keep re-sending the same batch');

    // Nothing is silently dropped: terminal rejections stay queued with the
    // reason recorded, for Settings -> Diagnostics.
    final remaining = await readOutbox(db);
    expect(remaining, hasLength(6));
    expect(
      remaining.every((e) => (e.lastError ?? '').contains('schema_invalid')),
      isTrue,
      reason: 'every quarantined entry must carry its reason',
    );
  });

  test('healthy rows still drain when they share the outbox with failures',
      () async {
    final repo = TestTasksRepo(db);
    for (final id in ['x', 'y', 'z']) {
      await _enqueueUnsendable(db, id);
    }
    await repo.upsert(id: 'good-1', title: 'Sendable');
    await repo.upsert(id: 'good-2', title: 'Also sendable');

    await engine.syncOnce();

    final remaining = await readOutbox(db);
    // The failures stay; both healthy rows are gone.
    expect(remaining.map((e) => e.rowId), containsAll(['x', 'y', 'z']));
    expect(remaining.map((e) => e.rowId),
        isNot(anyElement(anyOf('good-1', 'good-2'))));

    final good = await readTask(db, 'good-1');
    expect(good, isNotNull);
    expect(good!.dirty, isFalse,
        reason: 'a confirmed row must not stay dirty behind quarantined ones');
  });
}
