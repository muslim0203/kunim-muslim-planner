import 'package:drift/drift.dart';

import 'sync_column_mixin.dart';

/// One mood check-in per local day: the `mood_logs` entity of ADR-0002
/// conflict-matrix rule 11. Feature-owned by `features/mood/`.
///
/// - Natural key `(user_id, coalesce(ref_id, ''), date)`. [refId] is
///   reserved for more than one entry per day and is always null today.
/// - [date] holds the local calendar day as a UTC-midnight tag
///   (`LocalDay.toUtcMidnight`), exactly like `HabitLogs.date`.
/// - Server merge: [score] and [note] last-write-wins, [tags] set union.
///
/// There is deliberately no table-level UNIQUE on the natural key (a rule-14
/// tombstone must be storable, see `HabitLogs`); live-row uniqueness is the
/// partial index `ux_mood_logs_natural_key` created in `AppDatabase`.
class MoodLogs extends Table with SyncColumns {
  TextColumn get refId => text().nullable()();
  DateTimeColumn get date => dateTime()();

  /// 1 (very low) .. 5 (very good), see `MoodOptions`.
  IntColumn get score => integer()();

  /// JSON array of tag codes, e.g. `["calm","grateful"]`. Synced as a list.
  TextColumn get tags => text().withDefault(const Constant('[]'))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
