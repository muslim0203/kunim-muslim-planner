import 'package:drift/drift.dart';

import 'sync_column_mixin.dart';

/// A user-defined long-term goal (`docs/plan.md` §3 sync table list), e.g.
/// "Yiliga Qur'onni bir marta xatm qilish".
///
/// [progressPercent] is plain last-write-wins, deliberately NOT max-wins
/// (ADR-0002 conflict-matrix rule 18: "maqsad orqaga ham qaytishi mumkin" —
/// a goal's progress may legitimately be revised downward).
class Goals extends Table with SyncColumns {
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  IntColumn get progressPercent => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A checkpoint within a [Goals] row.
///
/// [goalId] is a logical reference to [Goals.id] — no SQL foreign key, for
/// the same reason [Tasks.categoryId] (`tasks_table.dart`) has none: pulled
/// rows for different sync entities can arrive in any order.
class Milestones extends Table with SyncColumns {
  TextColumn get goalId => text()();
  TextColumn get title => text()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
