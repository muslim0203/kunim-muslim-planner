/// Repository for the `task_categories` sync entity (ADR-0002 wire name
/// `task_categories`, `docs/sync-conflict-matrix.md` rule 20: plain LWW +
/// soft delete). Same rules as `task_repository.dart`: every mutation goes
/// through `writeWithOutbox`, every successful mutation calls
/// [onLocalWrite].
library;

import 'package:drift/drift.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/db/base_repository.dart';
import 'package:kunim/core/sync/conflict.dart' show toRfc3339Millis;
import 'package:uuid/uuid.dart';

class TaskCategoryRepository extends SyncableRepository {
  TaskCategoryRepository(super.db, {required this.onLocalWrite});

  /// Wire entity name — must match ADR-0002 /
  /// `apps/api/app/modules/sync/registry.py`'s `SYNC_ENTITIES` exactly.
  static const entity = 'task_categories';

  static const _uuid = Uuid();

  final void Function() onLocalWrite;

  // ------------------------------------------------------------------
  // Reads
  // ------------------------------------------------------------------

  /// All non-deleted categories, ordered by [TaskCategories.sortOrder]
  /// then creation time (stable tie-break for equal sort orders).
  Stream<List<TaskCategory>> watchAll({String? userId}) {
    final query = db.select(db.taskCategories)
      ..where((c) => c.deletedAt.isNull())
      ..orderBy([
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.createdAt),
      ]);
    if (userId != null) {
      query.where((c) => c.userId.equals(userId));
    }
    return query.watch();
  }

  Stream<TaskCategory?> watchById(String id) {
    final query = db.select(db.taskCategories)..where((c) => c.id.equals(id));
    return query.watchSingleOrNull();
  }

  Future<TaskCategory?> getById(String id) {
    final query = db.select(db.taskCategories)..where((c) => c.id.equals(id));
    return query.getSingleOrNull();
  }

  // ------------------------------------------------------------------
  // Mutations
  // ------------------------------------------------------------------

  Future<TaskCategory> createCategory({
    required String name,
    String? color,
    int sortOrder = 0,
    String? userId,
  }) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();

    final result = await writeWithOutbox<TaskCategory>(
      entity: entity,
      rowId: id,
      op: SyncOp.upsert,
      payload: _payload(
        id: id,
        userId: userId,
        name: name,
        color: color,
        sortOrder: sortOrder,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        serverVersion: 0,
      ),
      write: () async {
        await db.into(db.taskCategories).insert(
              TaskCategoriesCompanion.insert(
                id: Value(id),
                userId: Value(userId),
                name: name,
                color: Value(color),
                sortOrder: Value(sortOrder),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        return (db.select(db.taskCategories)..where((c) => c.id.equals(id)))
            .getSingle();
      },
    );
    onLocalWrite();
    return result;
  }

  Future<TaskCategory> updateCategory(
    String id, {
    String? name,
    Value<String?> color = const Value.absent(),
  }) async {
    final current = await _requireCategory(id);
    final now = DateTime.now().toUtc();

    final newName = name ?? current.name;
    final newColor = color.present ? color.value : current.color;

    final result = await writeWithOutbox<TaskCategory>(
      entity: entity,
      rowId: id,
      op: SyncOp.upsert,
      payload: _payload(
        id: id,
        userId: current.userId,
        name: newName,
        color: newColor,
        sortOrder: current.sortOrder,
        createdAt: current.createdAt,
        updatedAt: now,
        deletedAt: current.deletedAt,
        serverVersion: current.serverVersion,
      ),
      write: () async {
        await (db.update(db.taskCategories)..where((c) => c.id.equals(id)))
            .write(
          TaskCategoriesCompanion(
            name: Value(newName),
            color: Value(newColor),
            updatedAt: Value(now),
            dirty: const Value(true),
          ),
        );
        return (db.select(db.taskCategories)..where((c) => c.id.equals(id)))
            .getSingle();
      },
    );
    onLocalWrite();
    return result;
  }

  /// Soft-deletes a category (ADR-0002 §1 tombstone; never hard-deleted
  /// locally). Tasks referencing this category are left untouched —
  /// `tasks_table.dart` has no FK, and a task pointing at a deleted
  /// category is an expected, tolerated state (see
  /// `task_repository.dart`'s dangling-reference note).
  Future<void> softDeleteCategory(String id) async {
    final current = await _requireCategory(id);
    final now = DateTime.now().toUtc();

    await writeWithOutbox<void>(
      entity: entity,
      rowId: id,
      op: SyncOp.delete,
      payload: _payload(
        id: id,
        userId: current.userId,
        name: current.name,
        color: current.color,
        sortOrder: current.sortOrder,
        createdAt: current.createdAt,
        updatedAt: now,
        deletedAt: now,
        serverVersion: current.serverVersion,
      ),
      write: () =>
          (db.update(db.taskCategories)..where((c) => c.id.equals(id))).write(
        TaskCategoriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      ),
    );
    onLocalWrite();
  }

  /// Reassigns `sortOrder` for every id in [orderedIds] to its index in
  /// the list, e.g. after a drag-and-drop reorder. Each changed category
  /// is written through its own `writeWithOutbox` call (so each produces
  /// its own outbox entry and its own [onLocalWrite] call, matching "one
  /// mutation = one outbox entry" elsewhere in this file) — a category
  /// already at the right `sortOrder` is left untouched and produces no
  /// write at all.
  Future<void> reorderCategories(List<String> orderedIds) async {
    for (var index = 0; index < orderedIds.length; index++) {
      final id = orderedIds[index];
      final current = await _requireCategory(id);
      if (current.sortOrder == index) continue;
      final now = DateTime.now().toUtc();

      await writeWithOutbox<void>(
        entity: entity,
        rowId: id,
        op: SyncOp.upsert,
        payload: _payload(
          id: id,
          userId: current.userId,
          name: current.name,
          color: current.color,
          sortOrder: index,
          createdAt: current.createdAt,
          updatedAt: now,
          deletedAt: current.deletedAt,
          serverVersion: current.serverVersion,
        ),
        write: () =>
            (db.update(db.taskCategories)..where((c) => c.id.equals(id))).write(
          TaskCategoriesCompanion(
            sortOrder: Value(index),
            updatedAt: Value(now),
            dirty: const Value(true),
          ),
        ),
      );
      onLocalWrite();
    }
  }

  Future<TaskCategory> _requireCategory(String id) async {
    final row = await getById(id);
    if (row == null) {
      throw StateError('Task category not found: $id');
    }
    return row;
  }

  Map<String, dynamic> _payload({
    required String id,
    String? userId,
    required String name,
    String? color,
    required int sortOrder,
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
      'name': name,
      'color': color,
      'sort_order': sortOrder,
    };
  }
}
