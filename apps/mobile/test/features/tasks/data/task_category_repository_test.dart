// `TaskCategoryRepository` tests against a real in-memory Drift database —
// same style as `task_repository_test.dart`.
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/tasks/data/task_category_repository.dart';

void main() {
  late AppDatabase db;
  late int localWriteCalls;
  late TaskCategoryRepository repo;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    localWriteCalls = 0;
    repo = TaskCategoryRepository(db, onLocalWrite: () => localWriteCalls++);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<SyncOutboxData>> outboxFor(String rowId) {
    return (db.select(db.syncOutbox)..where((t) => t.rowId.equals(rowId)))
        .get();
  }

  group('createCategory', () {
    test('creates the row and exactly one outbox entry', () async {
      final category = await repo.createCategory(name: 'Ish');

      final outbox = await outboxFor(category.id);
      expect(outbox, hasLength(1));
      expect(outbox.single.entity, 'task_categories');
      expect(outbox.single.rowId, category.id);
      expect(outbox.single.op, 'upsert');
      expect(localWriteCalls, 1);
    });
  });

  group('updateCategory', () {
    test('updates fields and creates exactly one more outbox entry', () async {
      final created = await repo.createCategory(name: 'Ish', color: 'blue');
      localWriteCalls = 0;

      final updated = await repo.updateCategory(created.id,
          name: 'Ibodat', color: const Value('green'));

      expect(updated.name, 'Ibodat');
      expect(updated.color, 'green');
      final outbox = await outboxFor(created.id);
      expect(outbox, hasLength(2));
      expect(outbox.last.op, 'upsert');
      expect(outbox.last.entity, 'task_categories');
      expect(localWriteCalls, 1);
    });

    test('throws for an unknown id and does not call onLocalWrite', () async {
      await expectLater(
        repo.updateCategory('missing', name: 'x'),
        throwsA(isA<StateError>()),
      );
      expect(localWriteCalls, 0);
    });
  });

  group('softDeleteCategory', () {
    test('produces a delete op; row survives but leaves watchAll', () async {
      final created = await repo.createCategory(name: 'Temporary');
      localWriteCalls = 0;

      await repo.softDeleteCategory(created.id);

      final outbox = await outboxFor(created.id);
      expect(outbox, hasLength(2));
      expect(outbox.last.op, 'delete');
      expect(localWriteCalls, 1);

      final all = await repo.watchAll().first;
      expect(all.where((c) => c.id == created.id), isEmpty);

      final raw = await repo.getById(created.id);
      expect(raw, isNotNull);
      expect(raw!.deletedAt, isNotNull);
    });
  });

  group('reorderCategories', () {
    test('writes one outbox entry per changed category, in order', () async {
      final a = await repo.createCategory(name: 'A', sortOrder: 0);
      final b = await repo.createCategory(name: 'B', sortOrder: 1);
      final c = await repo.createCategory(name: 'C', sortOrder: 2);
      localWriteCalls = 0;

      await repo.reorderCategories([c.id, a.id, b.id]);

      // c: 2 -> 0 (changed), a: 0 -> 1 (changed), b: 1 -> 2 (changed): all
      // three actually move, so all three get one more outbox entry each.
      expect((await outboxFor(c.id)).last.op, 'upsert');
      expect((await outboxFor(a.id)).last.op, 'upsert');
      expect((await outboxFor(b.id)).last.op, 'upsert');
      expect(localWriteCalls, 3);

      final ordered = await repo.watchAll().first;
      expect(ordered.map((cat) => cat.id), [c.id, a.id, b.id]);
    });

    test('a category already at the target sortOrder is left untouched',
        () async {
      final a = await repo.createCategory(name: 'A', sortOrder: 0);
      final b = await repo.createCategory(name: 'B', sortOrder: 1);
      localWriteCalls = 0;

      await repo.reorderCategories([a.id, b.id]);

      expect(localWriteCalls, 0, reason: 'no category actually moved');
      expect((await outboxFor(a.id)), hasLength(1), reason: 'only creation');
      expect((await outboxFor(b.id)), hasLength(1), reason: 'only creation');
    });
  });
}
