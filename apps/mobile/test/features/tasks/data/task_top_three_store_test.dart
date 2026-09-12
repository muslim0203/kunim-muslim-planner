// `TaskTopThreeStore` tests. This store is intentionally NOT written
// through the sync outbox (see the class doc comment) — these tests
// assert that too: no `sync_outbox` row is ever created by pin/unpin.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/tasks/data/task_top_three_store.dart';
import 'package:kunim/features/tasks/domain/top_three_selection.dart';

void main() {
  late AppDatabase db;
  late TaskTopThreeStore store;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    store = TaskTopThreeStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('reads back an empty selection before anything is pinned', () async {
    final selection = await store.read();
    expect(selection.taskIds, isEmpty);
  });

  test('pin adds an id; unpin removes it', () async {
    await store.pin('task-1');
    await store.pin('task-2');
    expect((await store.read()).taskIds, ['task-1', 'task-2']);

    await store.unpin('task-1');
    expect((await store.read()).taskIds, ['task-2']);
  });

  test('pinning beyond maxSize drops the oldest pin', () async {
    await store.pin('a');
    await store.pin('b');
    await store.pin('c');
    await store.pin('d');

    final selection = await store.read();
    expect(selection.taskIds, ['b', 'c', 'd']);
    expect(selection.isFull, isTrue);
  });

  test('replace overwrites the whole selection', () async {
    await store.pin('a');
    await store.replace(['x', 'y']);
    expect((await store.read()).taskIds, ['x', 'y']);
  });

  test('watch() emits again after a pin', () async {
    final emissions = <TopThreeSelection>[];
    final subscription = store.watch().listen(emissions.add);

    await pumpEventQueue();
    expect(emissions, hasLength(1));
    expect(emissions.single.taskIds, isEmpty);

    await store.pin('task-1');
    await pumpEventQueue();
    expect(emissions, hasLength(2));
    expect(emissions.last.taskIds, ['task-1']);

    await subscription.cancel();
  });

  test('pin/unpin never write to the sync outbox', () async {
    await store.pin('task-1');
    await store.unpin('task-1');
    await store.replace(['a', 'b']);

    final outbox = await db.select(db.syncOutbox).get();
    expect(
      outbox,
      isEmpty,
      reason: 'the Top-3 pin list is local-only, never synced in phase 2',
    );
  });
}
