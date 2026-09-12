import 'package:drift/drift.dart';

import 'sync_column_mixin.dart';

/// A calendar entry (`docs/plan.md` §3 sync table list).
///
/// Recurring events are stored as a single row with an [rrule] string (an
/// RFC 5545 RRULE subset — "kalendar RRULE subset", `docs/plan.md` §12
/// phase-2 DoD): occurrences are expanded client-side at read time and are
/// never materialized as their own synced rows.
class CalendarEvents extends Table with SyncColumns {
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get startAt => dateTime()();

  /// Null for an open-ended/point-in-time event.
  DateTimeColumn get endAt => dateTime().nullable()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();

  /// RFC 5545 RRULE subset, e.g. `FREQ=WEEKLY;BYDAY=MO,WE`. Null for a
  /// one-off (non-recurring) event.
  TextColumn get rrule => text().nullable()();
  TextColumn get location => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
