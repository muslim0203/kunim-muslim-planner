/// Repository for the `tasks` sync entity (ADR-0002 wire name `tasks`,
/// `docs/sync-conflict-matrix.md` rules 1-8, 20). Every mutation goes
/// through `SyncableRepository.writeWithOutbox` — never `db.into(db.tasks)`
/// / `db.update(db.tasks)` directly — and every successful mutation calls
/// [onLocalWrite] so the "N=20 local writes" sync trigger
/// (`core/sync/sync_triggers.dart`) fires. [onLocalWrite] is injected
/// rather than read from a Riverpod `Ref` here so this class stays
/// constructible (and testable) with a plain spy callback, independent of
/// Riverpod; `application/task_providers.dart` wires the real
/// `SyncTriggerScheduler.onLocalWrite` in.
library;

import 'package:drift/drift.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/db/base_repository.dart';
import 'package:kunim/core/db/tables/tasks_table.dart' show TaskPriority;
import 'package:kunim/core/sync/conflict.dart' show toRfc3339Millis;
import 'package:uuid/uuid.dart';

class TaskRepository extends SyncableRepository {
  TaskRepository(super.db, {required this.onLocalWrite});

  /// Wire entity name — must match ADR-0002 and
  /// `apps/api/app/modules/sync/registry.py`'s `SYNC_ENTITIES` exactly.
  static const entity = 'tasks';

  static const _uuid = Uuid();

  /// Called once per successful mutation; never called if the mutation
  /// throws (the underlying `writeWithOutbox` transaction rolled back).
  final void Function() onLocalWrite;

  // ------------------------------------------------------------------
  // Reads (reactive via Drift `watch()`)
  // ------------------------------------------------------------------

  /// All non-deleted tasks, oldest-created first. `categoryId` is a loose
  /// reference (`tasks_table.dart` — no SQL FK by design): this query
  /// never joins against `TaskCategories`, so a task whose category has
  /// not synced yet, or was deleted on another device, still appears here
  /// unchanged.
  Stream<List<Task>> watchAll({String? userId}) {
    final query = db.select(db.tasks)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    if (userId != null) {
      query.where((t) => t.userId.equals(userId));
    }
    return query.watch();
  }

  /// Non-deleted tasks filed under [categoryId]. Matches on the raw
  /// column value only — a dangling/deleted category id still returns its
  /// tasks (see the class-level dangling-reference note).
  Stream<List<Task>> watchByCategory(String categoryId) {
    final query = db.select(db.tasks)
      ..where((t) => t.deletedAt.isNull() & t.categoryId.equals(categoryId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch();
  }

  /// A single task by id, including a soft-deleted one (so a screen that
  /// is already open on a task that gets deleted elsewhere can still
  /// render its last known state / an "this was deleted" message rather
  /// than crashing on a null). Emits `null` if the id does not exist at
  /// all.
  Stream<Task?> watchById(String id) {
    final query = db.select(db.tasks)..where((t) => t.id.equals(id));
    return query.watchSingleOrNull();
  }

  Future<Task?> getById(String id) {
    final query = db.select(db.tasks)..where((t) => t.id.equals(id));
    return query.getSingleOrNull();
  }

  // ------------------------------------------------------------------
  // Mutations
  // ------------------------------------------------------------------

  Future<Task> createTask({
    required String title,
    String? description,
    String? categoryId,
    TaskPriority priority = TaskPriority.medium,
    DateTime? dueDate,
    String? userId,
  }) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    final utcDueDate = dueDate?.toUtc();

    final result = await writeWithOutbox<Task>(
      entity: entity,
      rowId: id,
      op: SyncOp.upsert,
      payload: _payload(
        id: id,
        userId: userId,
        title: title,
        description: description,
        categoryId: categoryId,
        priority: priority,
        dueDate: utcDueDate,
        completedAt: null,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        serverVersion: 0,
      ),
      write: () async {
        await db.into(db.tasks).insert(
              TasksCompanion.insert(
                id: Value(id),
                userId: Value(userId),
                title: title,
                description: Value(description),
                categoryId: Value(categoryId),
                priority: Value(priority),
                dueDate: Value(utcDueDate),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        return (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle();
      },
    );
    onLocalWrite();
    return result;
  }

  /// Updates the editable fields of an existing task. A parameter left at
  /// its default `Value.absent()` keeps the current value; passing
  /// `Value(null)` for a nullable field clears it (e.g.
  /// `updateTask(id, categoryId: const Value(null))` removes the
  /// category). [title] and [priority] are non-nullable columns, so they
  /// use plain optional positional-style params instead.
  Future<Task> updateTask(
    String id, {
    String? title,
    Value<String?> description = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    TaskPriority? priority,
    Value<DateTime?> dueDate = const Value.absent(),
  }) async {
    final current = await _requireTask(id);
    final now = DateTime.now().toUtc();

    final newTitle = title ?? current.title;
    final newDescription =
        description.present ? description.value : current.description;
    final newCategoryId =
        categoryId.present ? categoryId.value : current.categoryId;
    final newPriority = priority ?? current.priority;
    final newDueDate =
        dueDate.present ? dueDate.value?.toUtc() : current.dueDate;

    final result = await writeWithOutbox<Task>(
      entity: entity,
      rowId: id,
      op: SyncOp.upsert,
      payload: _payload(
        id: id,
        userId: current.userId,
        title: newTitle,
        description: newDescription,
        categoryId: newCategoryId,
        priority: newPriority,
        dueDate: newDueDate,
        completedAt: current.completedAt,
        createdAt: current.createdAt,
        updatedAt: now,
        deletedAt: current.deletedAt,
        serverVersion: current.serverVersion,
      ),
      write: () async {
        await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
          TasksCompanion(
            title: Value(newTitle),
            description: Value(newDescription),
            categoryId: Value(newCategoryId),
            priority: Value(newPriority),
            dueDate: Value(newDueDate),
            updatedAt: Value(now),
            dirty: const Value(true),
          ),
        );
        return (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle();
      },
    );
    onLocalWrite();
    return result;
  }

  /// Sets or clears completion. See the ADR-0002 rule 8 note in
  /// `domain/task_status.dart`: this only ever writes `completedAt`
  /// itself (`null` to un-complete) — there is no `completed` boolean to
  /// keep in sync, and there never should be.
  Future<Task> setCompleted(String id, {required bool completed}) async {
    final current = await _requireTask(id);
    final now = DateTime.now().toUtc();
    final newCompletedAt = completed ? now : null;

    final result = await writeWithOutbox<Task>(
      entity: entity,
      rowId: id,
      op: SyncOp.upsert,
      payload: _payload(
        id: id,
        userId: current.userId,
        title: current.title,
        description: current.description,
        categoryId: current.categoryId,
        priority: current.priority,
        dueDate: current.dueDate,
        completedAt: newCompletedAt,
        createdAt: current.createdAt,
        updatedAt: now,
        deletedAt: current.deletedAt,
        serverVersion: current.serverVersion,
      ),
      write: () async {
        await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
          TasksCompanion(
            completedAt: Value(newCompletedAt),
            updatedAt: Value(now),
            dirty: const Value(true),
          ),
        );
        return (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle();
      },
    );
    onLocalWrite();
    return result;
  }

  Future<Task> completeTask(String id) => setCompleted(id, completed: true);

  /// Un-completes a task. See the ADR-0002 rule 8 warning above and on
  /// `domain/task_status.dart`: this can lose to an older completion from
  /// another device once synced, by design.
  Future<Task> uncompleteTask(String id) => setCompleted(id, completed: false);

  /// Soft-deletes a task (ADR-0002 §1: `deletedAt` tombstone; rows are
  /// never hard-deleted locally). The row remains in the table — callers
  /// needing "gone" semantics should filter on `deletedAt == null`, as
  /// [watchAll]/[watchByCategory] already do.
  Future<void> softDeleteTask(String id) async {
    final current = await _requireTask(id);
    final now = DateTime.now().toUtc();

    await writeWithOutbox<void>(
      entity: entity,
      rowId: id,
      op: SyncOp.delete,
      payload: _payload(
        id: id,
        userId: current.userId,
        title: current.title,
        description: current.description,
        categoryId: current.categoryId,
        priority: current.priority,
        dueDate: current.dueDate,
        completedAt: current.completedAt,
        createdAt: current.createdAt,
        updatedAt: now,
        deletedAt: now,
        serverVersion: current.serverVersion,
      ),
      write: () => (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      ),
    );
    onLocalWrite();
  }

  // NOTE on reordering: `TaskCategories` has a `sortOrder` column (see
  // `task_category_repository.dart#reorderCategories`), but `Tasks` does
  // not (`core/db/tables/tasks_table.dart`) — there is no generic
  // "reorder my task list" column to write through. The manual Top-3
  // pin *order* is modeled and persisted separately in
  // `domain/top_three_selection.dart` / `data/task_top_three_store.dart`,
  // which does not require a `Tasks` column.

  Future<Task> _requireTask(String id) async {
    final row = await getById(id);
    if (row == null) {
      throw StateError('Task not found: $id');
    }
    return row;
  }

  Map<String, dynamic> _payload({
    required String id,
    String? userId,
    required String title,
    String? description,
    String? categoryId,
    required TaskPriority priority,
    DateTime? dueDate,
    DateTime? completedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
    required int serverVersion,
  }) {
    return {
      'id': id,
      'user_id': userId,
      'created_at': toRfc3339Millis(createdAt),
      'updated_at': toRfc3339Millis(updatedAt),
      'deleted_at': deletedAt == null ? null : toRfc3339Millis(deletedAt),
      'server_version': serverVersion,
      'title': title,
      'description': description,
      'category_id': categoryId,
      'priority': priority.index,
      'due_date': dueDate == null ? null : toRfc3339Millis(dueDate),
      'completed_at': completedAt == null ? null : toRfc3339Millis(completedAt),
    };
  }
}
