// Push-side behavior of `SyncEngine.syncOnce()`: outbox drains in `seq`
// order, entries are removed only once the fake server confirms them, and
// batch size is capped at the server-*reported* limit rather than a
// hardcoded constant (ADR-0002 rule 5).
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
  late TestTasksRepo repo;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    server = FakeSyncServer();
    engine = SyncEngine(
      db: db,
      api: server,
      outboxDao: OutboxDao(db),
      stateStore: SyncStateStore(db),
    );
    repo = TestTasksRepo(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('drains the outbox and empties it once the server confirms', () async {
    await repo.upsert(id: 'a', title: 'First');
    await repo.upsert(id: 'b', title: 'Second');
    await repo.upsert(id: 'c', title: 'Third');

    expect(await readOutbox(db), hasLength(3));

    final status = await engine.syncOnce();

    expect(status, isA<SyncSuccess>());
    expect(await readOutbox(db), isEmpty);

    final taskA = await readTask(db, 'a');
    expect(taskA!.dirty, isFalse);
    expect(taskA.serverVersion, greaterThan(0));
  });

  test('respects the server-reported batch limit, not a hardcoded constant',
      () async {
    server = FakeSyncServer(maxChangesPerBatch: 2);
    engine = SyncEngine(
      db: db,
      api: server,
      outboxDao: OutboxDao(db),
      stateStore: SyncStateStore(db),
    );

    for (var i = 0; i < 5; i++) {
      await repo.upsert(id: 'row-$i', title: 'Task $i');
    }

    // FakeSyncServer.push throws if it ever receives more changes than its
    // own `maxChangesPerBatch` — the engine must have read that cap from
    // `fetchLimits()` and split the outbox into batches of at most 2.
    final status = await engine.syncOnce();

    expect(status, isA<SyncSuccess>());
    expect(await readOutbox(db), isEmpty);
    for (var i = 0; i < 5; i++) {
      expect((await readTask(db, 'row-$i'))!.dirty, isFalse);
    }
  });

  test('coalesced stale duplicates are cleaned up once the batch succeeds',
      () async {
    await repo.upsert(id: 'x', title: 'v1');
    await repo.upsert(id: 'x', title: 'v2');
    await repo.upsert(id: 'x', title: 'v3');
    expect(await readOutbox(db), hasLength(3));

    final status = await engine.syncOnce();

    expect(status, isA<SyncSuccess>());
    expect(await readOutbox(db), isEmpty);
    expect((await readTask(db, 'x'))!.title, 'v3');
  });
}
