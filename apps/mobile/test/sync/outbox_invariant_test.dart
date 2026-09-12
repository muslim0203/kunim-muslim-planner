// The single most important invariant in the sync design (ADR-0002 §2,
// `CLAUDE.md` rule 2): a local row write and its `sync_outbox` entry are
// written in ONE Drift transaction. This file proves that against a real
// (in-memory) database — including the failure path, not just the happy
// path.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/db/base_repository.dart';

/// Minimal stand-in for a real feature repository (e.g. the future
/// `features/tasks/data/tasks_repository.dart`), used only to exercise
/// [SyncableRepository.writeWithOutbox] the same way production code would.
class _TasksTestRepository extends SyncableRepository {
  _TasksTestRepository(super.db);

  Future<void> addTaskViaOutbox({
    required String id,
    required String title,
    Map<String, dynamic>? extraPayload,
  }) {
    return writeWithOutbox<void>(
      entity: 'tasks',
      rowId: id,
      op: SyncOp.upsert,
      payload: {
        'id': id,
        'title': title,
        ...?extraPayload,
      },
      write: () => db.into(db.tasks).insert(
            TasksCompanion.insert(id: Value(id), title: title),
          ),
    );
  }

  Future<void> softDeleteTask(String id, DateTime deletedAt) {
    return writeWithOutbox<void>(
      entity: 'tasks',
      rowId: id,
      op: SyncOp.delete,
      payload: {'id': id, 'deleted_at': deletedAt.toIso8601String()},
      write: () => (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
            deletedAt: Value(deletedAt), updatedAt: Value(deletedAt)),
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late _TasksTestRepository repo;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = _TasksTestRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('writing a row creates exactly one outbox entry, in the same write',
      () async {
    await repo.addTaskViaOutbox(id: 'task-1', title: 'Kunlik reja tuzish');

    final tasks = await db.select(db.tasks).get();
    final outbox = await db.select(db.syncOutbox).get();

    expect(tasks, hasLength(1));
    expect(outbox, hasLength(1));
    expect(outbox.single.entity, 'tasks');
    expect(outbox.single.rowId, 'task-1');
    expect(outbox.single.op, 'upsert');

    final decoded = jsonDecode(outbox.single.payload) as Map<String, dynamic>;
    expect(decoded['id'], 'task-1');
    expect(decoded['title'], 'Kunlik reja tuzish');
  });

  test('a soft delete produces a delete op, never an upsert', () async {
    await repo.addTaskViaOutbox(id: 'task-2', title: 'Vaqtinchalik vazifa');
    // The insert's outbox row is not what we assert on below; only the
    // delete's op matters for this test, so we don't touch it further.

    final deletedAt = DateTime.utc(2026, 9, 10);
    await repo.softDeleteTask('task-2', deletedAt);

    final row = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals('task-2')))
        .getSingle();
    expect(row.deletedAt, deletedAt);

    final outboxForRow = await (db.select(
      db.syncOutbox,
    )..where((t) => t.rowId.equals('task-2')))
        .get();
    // insert + delete = two outbox rows before any push-time coalescing;
    // the LATEST one for this row must be a delete.
    final latest = outboxForRow.reduce((a, b) => a.seq > b.seq ? a : b);
    expect(latest.op, 'delete');
  });

  test('payload must never contain the client-only dirty column', () async {
    expect(
      () => repo.addTaskViaOutbox(
        id: 'task-3',
        title: 'Bad payload',
        extraPayload: const {'dirty': true},
      ),
      throwsArgumentError,
    );

    // Nothing should have been written at all — the check runs before the
    // transaction opens.
    final tasks = await db.select(db.tasks).get();
    expect(tasks, isEmpty);
  });

  test(
    'if the outbox insert fails, the row write is rolled back too '
    '(atomicity, not just the happy path)',
    () async {
      // `jsonEncode` cannot encode a DateTime, so building the outbox
      // payload throws AFTER `write()` has already inserted the task row
      // inside the same transaction. This proves `db.transaction` rolls
      // both halves back together, not just that the happy path works.
      await expectLater(
        repo.addTaskViaOutbox(
          id: 'task-4',
          title: 'Should not survive',
          extraPayload: {'bad_field': DateTime.now()},
        ),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );

      final tasks = await db.select(db.tasks).get();
      final outbox = await db.select(db.syncOutbox).get();

      expect(
        tasks,
        isEmpty,
        reason: 'the task insert must have been rolled back',
      );
      expect(
        outbox,
        isEmpty,
        reason: 'no outbox entry should exist for the failed write either',
      );
    },
  );

  test('writeFromServer performs a plain write with no outbox side effect',
      () async {
    await repo.writeFromServer(() async {
      await db.into(db.tasks).insert(
            TasksCompanion.insert(
                id: const Value('task-5'), title: 'From pull'),
          );
    });

    final tasks = await db.select(db.tasks).get();
    final outbox = await db.select(db.syncOutbox).get();
    expect(tasks, hasLength(1));
    expect(
      outbox,
      isEmpty,
      reason: 'server-applied rows must not be re-queued for push',
    );
  });
}
