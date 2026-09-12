// `TaskRepository` tests against a real in-memory Drift database, following
// `test/sync/outbox_invariant_test.dart`'s style: every mutation must
// create exactly one outbox entry with the right `entity`/`rowId`/`op`,
// and `onLocalWrite` must fire on success and only on success.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/tasks/data/task_repository.dart';
import 'package:kunim/features/tasks/domain/task_status.dart';

void main() {
  late AppDatabase db;
  late int localWriteCalls;
  late TaskRepository repo;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    localWriteCalls = 0;
    repo = TaskRepository(db, onLocalWrite: () => localWriteCalls++);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<SyncOutboxData>> outboxFor(String rowId) {
    return (db.select(db.syncOutbox)..where((t) => t.rowId.equals(rowId)))
        .get();
  }

  group('createTask', () {
    test('creates the row and exactly one outbox entry', () async {
      final task = await repo.createTask(title: 'Buy groceries');

      expect(task.title, 'Buy groceries');
      expect(task.isCompleted, isFalse);

      final outbox = await outboxFor(task.id);
      expect(outbox, hasLength(1));
      expect(outbox.single.entity, 'tasks');
      expect(outbox.single.rowId, task.id);
      expect(outbox.single.op, 'upsert');
    });

    test('calls onLocalWrite exactly once on success', () async {
      await repo.createTask(title: 'A task');
      expect(localWriteCalls, 1);
    });
  });

  group('updateTask', () {
    test('updates fields and creates exactly one more outbox entry', () async {
      final created = await repo.createTask(title: 'Original title');
      localWriteCalls = 0;

      final updated = await repo.updateTask(created.id, title: 'New title');

      expect(updated.title, 'New title');
      final outbox = await outboxFor(created.id);
      expect(outbox, hasLength(2), reason: 'create + update = 2 entries');
      expect(outbox.last.op, 'upsert');
      expect(outbox.last.entity, 'tasks');
      expect(outbox.last.rowId, created.id);
      expect(localWriteCalls, 1);
    });

    test('throws for an unknown id and does not call onLocalWrite', () async {
      await expectLater(
        repo.updateTask('does-not-exist', title: 'x'),
        throwsA(isA<StateError>()),
      );
      expect(localWriteCalls, 0);
    });
  });

  group('completion', () {
    test('completeTask sets completedAt and isCompleted follows', () async {
      final created = await repo.createTask(title: 'Task');
      localWriteCalls = 0;

      final completed = await repo.completeTask(created.id);

      expect(completed.completedAt, isNotNull);
      expect(completed.isCompleted, isTrue);
      final outbox = await outboxFor(created.id);
      expect(outbox, hasLength(2));
      expect(outbox.last.op, 'upsert');
      expect(localWriteCalls, 1);
    });

    test('uncompleteTask sets completedAt back to null', () async {
      final created = await repo.createTask(title: 'Task');
      await repo.completeTask(created.id);
      localWriteCalls = 0;

      final uncompleted = await repo.uncompleteTask(created.id);

      expect(uncompleted.completedAt, isNull);
      expect(uncompleted.isCompleted, isFalse);
      final outbox = await outboxFor(created.id);
      expect(outbox, hasLength(3), reason: 'create + complete + uncomplete');
      expect(outbox.last.op, 'upsert');
      expect(localWriteCalls, 1);
    });

    test('onLocalWrite is not called when completing an unknown id', () async {
      await expectLater(
        repo.completeTask('missing'),
        throwsA(isA<StateError>()),
      );
      expect(localWriteCalls, 0);
    });
  });

  group('softDeleteTask', () {
    test(
        'produces a delete op and the row disappears from list queries '
        'but still exists in the table', () async {
      final created = await repo.createTask(title: 'To be deleted');
      localWriteCalls = 0;

      await repo.softDeleteTask(created.id);

      final outbox = await outboxFor(created.id);
      expect(outbox, hasLength(2));
      expect(outbox.last.op, 'delete');
      expect(outbox.last.entity, 'tasks');
      expect(outbox.last.rowId, created.id);
      expect(localWriteCalls, 1);

      final all = await repo.watchAll().first;
      expect(all.where((t) => t.id == created.id), isEmpty);

      final rawRow = await repo.getById(created.id);
      expect(rawRow, isNotNull, reason: 'soft delete never removes the row');
      expect(rawRow!.deletedAt, isNotNull);
      expect(rawRow.isDeleted, isTrue);
    });

    test('throws for an unknown id and does not call onLocalWrite', () async {
      await expectLater(
        repo.softDeleteTask('missing'),
        throwsA(isA<StateError>()),
      );
      expect(localWriteCalls, 0);
    });
  });

  group('dangling categoryId', () {
    test(
        'a task referencing a non-existent category still appears in '
        'watchAll and watchByCategory', () async {
      final task = await repo.createTask(
        title: 'Orphaned task',
        categoryId: 'category-that-does-not-exist',
      );

      final all = await repo.watchAll().first;
      expect(all.map((t) => t.id), contains(task.id));

      final byCategory =
          await repo.watchByCategory('category-that-does-not-exist').first;
      expect(byCategory.map((t) => t.id), contains(task.id));
    });
  });

  group('reactive watch()', () {
    test('watchAll emits again after a mutation', () async {
      final emissions = <int>[];
      final subscription =
          repo.watchAll().listen((tasks) => emissions.add(tasks.length));

      await pumpEventQueue();
      expect(emissions, [0]);

      await repo.createTask(title: 'New task');
      await pumpEventQueue();
      expect(emissions, [0, 1]);

      await subscription.cancel();
    });

    test('watchById emits again after the task changes', () async {
      final created = await repo.createTask(title: 'Watched task');
      final emissions = <bool?>[];
      final subscription = repo
          .watchById(created.id)
          .listen((task) => emissions.add(task?.isCompleted));

      await pumpEventQueue();
      expect(emissions, [false]);

      await repo.completeTask(created.id);
      await pumpEventQueue();
      expect(emissions, [false, true]);

      await subscription.cancel();
    });
  });
}
