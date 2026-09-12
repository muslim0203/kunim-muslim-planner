// Pull-side behavior: pagination across `has_more`, and the cursor never
// advancing when applying a page throws (ADR-0002 rule 7 — a crash
// mid-page must not skip rows on the next attempt).
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/outbox.dart';
import 'package:kunim/core/sync/sync_engine.dart';

import 'sync_engine_fake_server.dart';
import 'sync_engine_test_helpers.dart';

void main() {
  late AppDatabase db;
  late FakeSyncServer server;
  late SyncEngine engine;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('paginates across has_more and applies every seeded row', () async {
    server = FakeSyncServer(maxPullLimit: 2);
    for (var i = 0; i < 5; i++) {
      server.seedServerRow(
        'tasks',
        buildTaskRow(id: 'row-$i', title: 'Task $i'),
      );
    }
    engine = SyncEngine(
      db: db,
      api: server,
      outboxDao: OutboxDao(db),
      stateStore: SyncStateStore(db),
    );

    final status = await engine.syncOnce();

    expect(status, isA<SyncSuccess>());
    for (var i = 0; i < 5; i++) {
      final task = await readTask(db, 'row-$i');
      expect(task, isNotNull, reason: 'row-$i should have been pulled');
      expect(task!.dirty, isFalse);
    }
    expect(await SyncStateStore(db).getCursor(), server.currentMaxVersion);
  });

  test('cursor does not advance when applying a page throws', () async {
    server = FakeSyncServer(maxPullLimit: 10);
    server.seedServerRow('tasks', buildTaskRow(id: 'good', title: 'Good'));
    // An entity this client build has no local table for at all would just
    // be skipped (forward-compat) rather than throw, so to prove the
    // "don't advance the cursor on a mid-page failure" contract we instead
    // seed a row that IS for a known entity but is missing a
    // non-nullable column (`title`), which makes `Task.fromJson` throw
    // while decoding it — a stand-in for "applying this row failed".
    server.seedServerRow('tasks', {
      'id': 'broken',
      'user_id': null,
      'created_at': '2026-09-12T08:00:00.000Z',
      'updated_at': '2026-09-12T08:00:00.000Z',
      'deleted_at': null,
      'server_version': 0,
      // 'title' deliberately omitted.
      'description': null,
      'category_id': null,
      'priority': 1,
      'due_date': null,
      'completed_at': null,
    });

    engine = SyncEngine(
      db: db,
      api: server,
      outboxDao: OutboxDao(db),
      stateStore: SyncStateStore(db),
    );

    final stateStore = SyncStateStore(db);
    expect(await stateStore.getCursor(), 0);

    await expectLater(engine.syncOnce(), throwsA(anything));

    // The page (both rows) was applied inside one transaction that threw
    // on the second row, so the first row's write must have rolled back
    // too, and the cursor must still be at 0.
    expect(await stateStore.getCursor(), 0);
    expect(await readTask(db, 'good'), isNull);
  });
}
