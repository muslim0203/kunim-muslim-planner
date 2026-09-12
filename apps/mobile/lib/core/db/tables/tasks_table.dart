import 'package:drift/drift.dart';

import 'sync_column_mixin.dart';

/// Task urgency, persisted as an int via Drift's [intEnum] (the column
/// stores `TaskPriority.index`). Enum member ORDER is therefore part of the
/// on-disk/wire format — never reorder or remove existing values, only
/// append new ones.
enum TaskPriority { low, medium, high }

/// A user-defined bucket a [Tasks] row can be filed under (e.g. "Ish",
/// "Ibodat"). Feature-owned by `features/tasks/` per `CLAUDE.md` ("har
/// jadval core/db/tables da, egasi bitta feature").
class TaskCategories extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A single to-do item (`docs/plan.md` §3 sync table list).
///
/// - [categoryId] is a logical reference to [TaskCategories.id]. There is
///   deliberately no SQL foreign key: pulled rows for different sync
///   entities can arrive in any order, and an FK would turn pull ordering
///   into a correctness requirement instead of a UX nicety. Referential
///   integrity across entities is a feature-layer/UI concern.
/// - [completedAt] is the ONLY source of truth for "done" — ADR-0002
///   conflict-matrix rule 8: a `completed` boolean is never synced; it is
///   always derived as `completedAt != null`. `completedAt` merges
///   max-wins (a sync can never turn a task back to "not done").
class Tasks extends Table with SyncColumns {
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get categoryId => text().nullable()();

  /// See [TaskPriority]. Defaults to `medium` (index 1).
  IntColumn get priority =>
      intEnum<TaskPriority>().withDefault(const Constant(1))();

  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
