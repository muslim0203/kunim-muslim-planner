// ADR-0002 §4 `full_resync_required` recovery: wipe locally-clean
// server-derived state, reset the cursor to 0, and pull everything again —
// while an unpushed local edit (`dirty = 1`, still sitting in the outbox)
// must never be lost. This is the task brief's "worst possible bug" to
// get wrong, so it gets its own dedicated test.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
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
      'full_resync_required resets and resyncs without losing an unpushed '
      'local edit', () async {
    // 1. Device is already caught up on some old, now-clean (pushed and
    // pulled) server rows.
    await repo.upsert(id: 'old-1', title: 'Old row 1');
    await engine.syncOnce();
    expect((await readTask(db, 'old-1'))!.dirty, isFalse);

    // 2. The device drifts far behind (simulated: nothing new happens for
    // "a long time"), and meanwhile also makes a brand-new, still-unpushed
    // local edit.
    await repo.upsert(id: 'unsynced', title: 'Not pushed yet');
    expect(await readOutbox(db), hasLength(1));

    // 3. The server has since purged tombstones past this device's
    // cursor; the next pull answers `full_resync_required: true`.
    final cursorBefore = await SyncStateStore(db).getCursor();
    server.simulatePurgeBeyond(cursorBefore + 1);
    // Also seed a couple of rows the fresh full pull should pick back up.
    server.seedServerRow(
      'tasks',
      buildTaskRow(id: 'server-1', title: 'From server after resync'),
    );

    final status = await engine.syncOnce();
    expect(status, isA<SyncSuccess>());

    // The unpushed edit survived the wipe and WAS pushed as part of this
    // same cycle (resync purges clean rows, resets cursor, pulls, then the
    // ADR says the outbox is pushed as usual afterwards — but since this
    // engine pushes BEFORE pulling each cycle, the edit was already pushed
    // before the resync was even discovered; either way it must not be
    // gone).
    final unsynced = await readTask(db, 'unsynced');
    expect(unsynced, isNotNull, reason: 'unpushed edit must survive resync');
    expect(unsynced!.title, 'Not pushed yet');

    // The old clean row was wiped by the purge step and must have come
    // back via the fresh full pull (it's still on the server).
    final old1 = await readTask(db, 'old-1');
    expect(old1, isNotNull);
    expect(old1!.dirty, isFalse);

    // The new server-side row from the fresh pull must be present too.
    final server1 = await readTask(db, 'server-1');
    expect(server1, isNotNull);

    // Cursor must reflect the fresh full pull, not be stuck at 0.
    expect(await SyncStateStore(db).getCursor(), server.currentMaxVersion);
  });

  test(
      'purgeCleanRows never deletes a row that is still dirty (unpushed) '
      'at the moment a resync runs', () async {
    // Establish a nonzero cursor first — `cursor == 0` is exempt from the
    // purge-watermark check (a fresh device is always valid), so a resync
    // can only be observed once the device has synced at least once.
    await repo.upsert(id: 'seed', title: 'Seed');
    await engine.syncOnce();
    final cursorBefore = await SyncStateStore(db).getCursor();
    expect(cursorBefore, greaterThan(0));

    // Force this row to fail the push step itself (schema_invalid: no
    // `updated_at` in the payload), so it is STILL dirty=1 in the outbox
    // by the time the pull phase discovers full_resync_required in the
    // very same cycle — the scenario purgeCleanRows's `WHERE dirty = 0`
    // must get right.
    await db.transaction(() async {
      await db.into(db.tasks).insert(
            TasksCompanion.insert(
              id: const Value('stuck'),
              title: 'Still mid-flight',
              dirty: const Value(true),
              createdAt: Value(DateTime.now().toUtc()),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
      await db.into(db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              entity: 'tasks',
              rowId: 'stuck',
              op: 'upsert',
              payload: jsonEncode(const {
                'id': 'stuck',
                'title': 'Still mid-flight',
                // 'updated_at' intentionally missing -> schema_invalid.
              }),
            ),
          );
    });

    server.simulatePurgeBeyond(cursorBefore + 1);

    final status = await engine.syncOnce();
    expect(status, isA<SyncSuccess>());

    final stuck = await readTask(db, 'stuck');
    expect(stuck, isNotNull, reason: 'a dirty row must survive the purge');
    expect(stuck!.dirty, isTrue);
  });
}
