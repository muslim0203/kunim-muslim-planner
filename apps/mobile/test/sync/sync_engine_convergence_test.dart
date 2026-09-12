// Phase-2 Definition of Done (docs/adr/0002-sync.md §"Konflikt matritsasi",
// "Test majburiyati"): two devices edit offline, then sync — they converge
// to the same state and neither loses a write. Two independent in-memory
// Drift databases (two "devices") share one `FakeSyncServer` (the one
// backend both talk to).
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/outbox.dart';
import 'package:kunim/core/sync/sync_engine.dart';

import 'sync_engine_fake_server.dart';
import 'sync_engine_test_helpers.dart';

void main() {
  // Two `AppDatabase` instances legitimately coexist in this file (they
  // model two separate physical devices, each with its own in-memory
  // executor) — silence drift's single-process-multiple-databases warning,
  // which assumes that pattern is always a bug.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
      'two offline devices each create their own rows, then both sync and '
      'converge without losing either write', () async {
    final server = FakeSyncServer();

    final dbA = AppDatabase.withExecutor(NativeDatabase.memory());
    final engineA = SyncEngine(
      db: dbA,
      api: server,
      outboxDao: OutboxDao(dbA),
      stateStore: SyncStateStore(dbA),
    );
    final repoA = TestTasksRepo(dbA);

    final dbB = AppDatabase.withExecutor(NativeDatabase.memory());
    final engineB = SyncEngine(
      db: dbB,
      api: server,
      outboxDao: OutboxDao(dbB),
      stateStore: SyncStateStore(dbB),
    );
    final repoB = TestTasksRepo(dbB);

    try {
      // Both devices are offline and edit independently — different rows,
      // so there is no genuine field-level conflict to resolve (ADR-0002
      // explicitly accepts that a *true* same-row conflict can lose the
      // losing edit's fields under LWW; convergence without loss is
      // guaranteed for non-overlapping edits, which is the realistic
      // common case this DoD targets).
      await repoA.upsert(id: 'from-a', title: 'Written on device A');
      await repoB.upsert(id: 'from-b', title: 'Written on device B');

      // Now both come online: A syncs first, then B.
      final statusA1 = await engineA.syncOnce();
      expect(statusA1, isA<SyncSuccess>());
      final statusB1 = await engineB.syncOnce();
      expect(statusB1, isA<SyncSuccess>());

      // A hasn't seen B's row yet (A already pulled before B pushed) —
      // one more sync catches it up.
      final statusA2 = await engineA.syncOnce();
      expect(statusA2, isA<SyncSuccess>());

      // Both devices must now agree on both rows.
      for (final db in [dbA, dbB]) {
        final a = await readTask(db, 'from-a');
        final b = await readTask(db, 'from-b');
        expect(a, isNotNull, reason: 'device-A write must not be lost');
        expect(b, isNotNull, reason: 'device-B write must not be lost');
        expect(a!.title, 'Written on device A');
        expect(b!.title, 'Written on device B');
        expect(a.dirty, isFalse);
        expect(b.dirty, isFalse);
      }

      // Neither device has anything left to push.
      expect(await readOutbox(dbA), isEmpty);
      expect(await readOutbox(dbB), isEmpty);
    } finally {
      await dbA.close();
      await dbB.close();
    }
  });
}
