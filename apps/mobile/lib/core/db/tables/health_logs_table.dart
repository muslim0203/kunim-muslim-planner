import 'package:drift/drift.dart';

import 'sync_column_mixin.dart';

/// One local day's health numbers: the `health_logs` entity of ADR-0002
/// conflict-matrix rule 13. Feature-owned by `features/health/`.
///
/// - Natural key `(user_id, coalesce(ref_id, ''), date)`; [refId] is always
///   null today.
/// - [waterMl], [steps], [workoutMin] and [calories] are additive and merge
///   max-wins on the server; [weightKg] and [note] are last-write-wins.
/// - Every metric is optional: a day may record only water, only weight, ...
///
/// Live-row uniqueness is the partial index `ux_health_logs_natural_key`.
class HealthLogs extends Table with SyncColumns {
  TextColumn get refId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  IntColumn get waterMl => integer().nullable()();
  IntColumn get steps => integer().nullable()();
  IntColumn get workoutMin => integer().nullable()();
  IntColumn get calories => integer().nullable()();
  RealColumn get weightKg => real().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
