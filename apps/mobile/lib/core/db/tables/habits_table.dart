import 'package:drift/drift.dart';

import 'sync_column_mixin.dart';

/// A recurring habit definition (`docs/plan.md` §3 sync table list), e.g.
/// "Kunlik 2 sahifa Qur'on o'qish".
class Habits extends Table with SyncColumns {
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();

  /// Free-form cadence, e.g. `'daily'`, `'weekly'`. Kept as text rather
  /// than a Drift enum: the exact cadence vocabulary is still open
  /// (`docs/plan.md` §12 phase-2 scope) and it is not sync/merge-critical
  /// (ADR-0002 conflict matrix rule 20: plain LWW).
  TextColumn get frequency => text().withDefault(const Constant('daily'))();
  IntColumn get targetCount => integer().withDefault(const Constant(1))();
  TextColumn get color => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A single day's completion log for a [Habits] row.
///
/// This is the `habit_logs` entity from ADR-0002 conflict-matrix rule 9:
/// the natural key is **`(userId, habitId, date)`** — [habitId] is what the
/// ADR calls `ref_id` for this entity. A device must never hold two live
/// (non-deleted) rows for the same habit on the same day; [date] must be
/// truncated to a day boundary (UTC midnight) by callers before insert, so
/// the natural key is stable regardless of time-of-day.
///
/// [count]/[value] are the "additive" fields the server merges with
/// max-wins (never last-write-wins) so one device logging "drank water"
/// can never be clobbered by another device's stale copy; [note] is plain
/// LWW.
class HabitLogs extends Table with SyncColumns {
  /// `ref_id` per ADR-0002 rule 9 — the [Habits.id] this log entry belongs
  /// to.
  TextColumn get habitId => text()();
  DateTimeColumn get date => dateTime()();
  IntColumn get count => integer().withDefault(const Constant(1))();
  RealColumn get value => real().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {userId, habitId, date},
      ];
}
