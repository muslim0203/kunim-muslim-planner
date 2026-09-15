import 'package:drift/drift.dart';

import 'sync_column_mixin.dart';

/// How one of the day's five prayers was marked: the `prayer_logs` entity of
/// ADR-0002 conflict-matrix rule 10. Feature-owned by `features/prayer/`.
///
/// - Natural key `(user_id, ref_id, date)`. [refId] is the prayer key
///   (`fajr`, `dhuhr`, `asr`, `maghrib`, `isha`) and is never null.
/// - [date] holds the prayer's local calendar day as a UTC-midnight tag
///   (`LocalDay.toUtcMidnight`), exactly like `HabitLogs.date`.
/// - Server merge: [status] is an ordered enum, max-wins
///   (`none < qaza < alone < jamaah`); [note] last-write-wins.
///
/// There is deliberately no table-level UNIQUE on the natural key (a rule-14
/// tombstone must be storable, see `HabitLogs`); live-row uniqueness is the
/// partial index `ux_prayer_logs_natural_key` created in `AppDatabase`.
class PrayerLogs extends Table with SyncColumns {
  TextColumn get refId => text()();
  DateTimeColumn get date => dateTime()();

  /// Wire code of `PrayerLogStatus`.
  TextColumn get status => text()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
