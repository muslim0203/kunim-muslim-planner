// Shared local-database test helpers for `sync_engine_*_test.dart`: seeding
// a `tasks` row + its outbox entry the same way a real feature repository
// would (through `SyncableRepository.writeWithOutbox`, never a raw
// `into(db.tasks)`), and reading a row back for assertions.
import 'package:drift/drift.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/db/base_repository.dart';

import 'sync_engine_fake_server.dart';

/// A minimal stand-in for a feature repository (e.g. `TasksRepository`,
/// not yet built) — exists only so these tests go through the same
/// `writeWithOutbox` invariant real code must use, instead of poking the
/// table directly.
class TestTasksRepo extends SyncableRepository {
  TestTasksRepo(super.db);

  Future<void> upsert({
    required String id,
    required String title,
    DateTime? updatedAt,
    DateTime? createdAt,
  }) {
    final row = buildTaskRow(
      id: id,
      title: title,
      updatedAt: updatedAt,
      createdAt: createdAt,
    );
    return writeWithOutbox(
      entity: 'tasks',
      rowId: id,
      op: SyncOp.upsert,
      payload: syncPayload(row),
      write: () => db.into(db.tasks).insertOnConflictUpdate(
            TasksCompanion.insert(
              id: Value(id),
              title: title,
              dirty: const Value(true),
              updatedAt: Value(updatedAt ?? DateTime.now().toUtc()),
              createdAt:
                  Value(createdAt ?? updatedAt ?? DateTime.now().toUtc()),
            ),
          ),
    );
  }
}

Future<Task?> readTask(AppDatabase db, String id) {
  return (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();
}

Future<List<SyncOutboxData>> readOutbox(AppDatabase db) {
  return db.select(db.syncOutbox).get();
}
