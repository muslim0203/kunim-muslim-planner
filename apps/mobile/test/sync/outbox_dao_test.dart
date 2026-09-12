// Tests for `OutboxDao` (ADR-0002 §2): stable seq ordering, coalescing of
// repeated writes to the same row (without losing a trailing delete),
// attempts/last_error bookkeeping, and removal only on acknowledgement.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/db/base_repository.dart';
import 'package:kunim/core/sync/outbox.dart';

Future<int> _enqueue(
  AppDatabase db, {
  required String entity,
  required String rowId,
  required SyncOp op,
  required Map<String, dynamic> payload,
}) async {
  return db.transaction(() async {
    return db.into(db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            entity: entity,
            rowId: rowId,
            op: op.name,
            payload: jsonEncode(payload),
          ),
        );
  });
}

void main() {
  late AppDatabase db;
  late OutboxDao dao;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    dao = OutboxDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('allPendingOrdered is stable by seq ascending', () async {
    await _enqueue(db,
        entity: 'tasks', rowId: 'a', op: SyncOp.upsert, payload: {'v': 1});
    await _enqueue(db,
        entity: 'tasks', rowId: 'b', op: SyncOp.upsert, payload: {'v': 2});
    await _enqueue(db,
        entity: 'habits', rowId: 'c', op: SyncOp.upsert, payload: {'v': 3});

    final all = await dao.allPendingOrdered();
    expect(all.map((e) => e.rowId).toList(), ['a', 'b', 'c']);
    expect(all.map((e) => e.seq).toList(), orderedEquals([1, 2, 3]));
  });

  test('nextBatch coalesces repeated upserts of the same row to the latest',
      () async {
    await _enqueue(db,
        entity: 'tasks', rowId: 'x', op: SyncOp.upsert, payload: {'v': 'v1'});
    await _enqueue(db,
        entity: 'tasks', rowId: 'x', op: SyncOp.upsert, payload: {'v': 'v2'});
    await _enqueue(db,
        entity: 'tasks', rowId: 'x', op: SyncOp.upsert, payload: {'v': 'v3'});

    final batch = await dao.nextBatch(200);
    expect(batch, hasLength(1));
    expect(batch.single.payload['v'], 'v3');
    expect(batch.single.seq, 3);
  });

  test('nextBatch never loses a trailing delete after earlier upserts',
      () async {
    await _enqueue(db,
        entity: 'tasks',
        rowId: 'y',
        op: SyncOp.upsert,
        payload: {'v': 'created'});
    await _enqueue(db,
        entity: 'tasks',
        rowId: 'y',
        op: SyncOp.upsert,
        payload: {'v': 'edited'});
    await _enqueue(db,
        entity: 'tasks', rowId: 'y', op: SyncOp.delete, payload: {'v': 'gone'});

    final batch = await dao.nextBatch(200);
    expect(batch, hasLength(1));
    expect(batch.single.op, SyncOp.delete);
  });

  test('nextBatch preserves seq order across distinct rows and caps at limit',
      () async {
    for (var i = 0; i < 5; i++) {
      await _enqueue(
        db,
        entity: 'tasks',
        rowId: 'row-$i',
        op: SyncOp.upsert,
        payload: {'v': i},
      );
    }

    final batch = await dao.nextBatch(3);
    expect(batch, hasLength(3));
    expect(batch.map((e) => e.rowId).toList(), ['row-0', 'row-1', 'row-2']);
  });

  test('acknowledge removes exactly the given seqs', () async {
    final seq1 = await _enqueue(db,
        entity: 'tasks', rowId: 'a', op: SyncOp.upsert, payload: {'v': 1});
    await _enqueue(db,
        entity: 'tasks', rowId: 'b', op: SyncOp.upsert, payload: {'v': 2});

    await dao.acknowledge([seq1]);

    final remaining = await dao.allPendingOrdered();
    expect(remaining.map((e) => e.rowId), ['b']);
  });

  test(
      'recordFailure increments attempts and stores last_error without '
      'deleting the row', () async {
    final seq = await _enqueue(
      db,
      entity: 'tasks',
      rowId: 'a',
      op: SyncOp.upsert,
      payload: {'v': 1},
    );

    await dao.recordFailure(seq, error: 'network timeout');
    await dao.recordFailure(seq, error: 'network timeout again');

    final entries = await dao.allPendingOrdered();
    expect(entries, hasLength(1));
    expect(entries.single.attempts, 2);
    expect(entries.single.lastError, 'network timeout again');
  });
}
