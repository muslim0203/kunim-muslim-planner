import 'package:drift/drift.dart';

import 'sync_column_mixin.dart';

/// One night's sleep, filed under the local day the user woke up: the
/// `sleep_logs` entity of ADR-0002 conflict-matrix rule 12. Feature-owned by
/// `features/sleep/`.
///
/// - Natural key `(user_id, coalesce(ref_id, ''), date)`; [refId] is always
///   null today.
/// - [bedTime]/[wakeTime] are real UTC instants and merge as one
///   last-write-wins pair; [durationMin] is derived from them
///   (`floor((wake - bed) / 1 min)`) and is never merged on its own.
/// - [quality] and [note] are last-write-wins.
///
/// Live-row uniqueness is the partial index `ux_sleep_logs_natural_key`.
class SleepLogs extends Table with SyncColumns {
  TextColumn get refId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get bedTime => dateTime()();
  DateTimeColumn get wakeTime => dateTime()();
  IntColumn get durationMin => integer()();

  /// 1 (poor) .. 5 (excellent), or null when not rated.
  IntColumn get quality => integer().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
