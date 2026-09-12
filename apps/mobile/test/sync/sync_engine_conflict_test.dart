// `conflict.dart` behavior driven end-to-end through `SyncEngine`: a
// `conflict` push result must overwrite the local row with `server_row`
// and must NOT create a new outbox entry (a regression here is an
// infinite sync loop — the row would look dirty again, get re-pushed,
// conflict again, forever). Also covers the `updated_at_in_future`
// rejection: re-stamp with `now()` and succeed on retry.
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

  test(
      'a conflict result overwrites the local row with server_row and '
      'creates no new outbox entry', () async {
    // Seed the server with a row already newer than what the client is
    // about to push, forcing rule 2/4 ("server wins").
    final serverWinTime = DateTime.utc(2026, 9, 12, 10);
    server.seedServerRow(
      'tasks',
      buildTaskRow(id: 'x', title: 'Server title', updatedAt: serverWinTime),
    );

    await repo.upsert(
      id: 'x',
      title: 'Client title',
      updatedAt: serverWinTime.subtract(const Duration(hours: 1)),
    );
    expect(await readOutbox(db), hasLength(1));

    final status = await engine.syncOnce();

    expect(status, isA<SyncSuccess>());
    // The conflict is resolved AND the pull that follows re-applies the
    // same row idempotently — either way the outbox must end up empty.
    expect(await readOutbox(db), isEmpty);

    final local = await readTask(db, 'x');
    expect(local!.title, 'Server title');
    expect(local.dirty, isFalse);

    // Proving the "no infinite loop" property directly: running another
    // cycle must not re-push anything for this row.
    final secondStatus = await engine.syncOnce();
    expect(secondStatus, isA<SyncSuccess>());
    expect(await readOutbox(db), isEmpty);
  });

  test('updated_at_in_future is re-stamped and succeeds on retry', () async {
    final farFuture = DateTime.now().toUtc().add(const Duration(days: 3));
    await repo.upsert(id: 'y', title: 'From the future', updatedAt: farFuture);

    final firstStatus = await engine.syncOnce();
    expect(firstStatus, isA<SyncSuccess>());

    // Still in the outbox (re-queued under a new seq), not dropped, and
    // the local row's updated_at must have been corrected already.
    final pendingAfterFirst = await readOutbox(db);
    expect(pendingAfterFirst, hasLength(1));
    final localAfterFirst = await readTask(db, 'y');
    expect(
      localAfterFirst!.updatedAt.isAfter(farFuture.subtract(
        const Duration(days: 1),
      )),
      isFalse,
      reason: 'updated_at must have been re-stamped to roughly now(), '
          'not left in the future',
    );

    final secondStatus = await engine.syncOnce();
    expect(secondStatus, isA<SyncSuccess>());
    expect(await readOutbox(db), isEmpty);
    expect((await readTask(db, 'y'))!.dirty, isFalse);
  });
}
