import 'package:drift/drift.dart';

import 'sync_column_mixin.dart';

/// One day's points: the `daily_scores` entity of ADR-0002 rule 26.
/// Feature-owned by `features/stats/`.
///
/// - Natural key `(user_id, date)`: a day has exactly one score, so there is
///   no `ref_id` here.
/// - [date] holds the local calendar day as a UTC-midnight tag
///   (`LocalDay.toUtcMidnight`), like every other dated row.
/// - The points are computed on the device
///   (`features/stats/domain/daily_score.dart`) and synced like any other
///   row; the server only adds them up for the leaderboard. Server merge:
///   [points], [done] and [planned] are max-wins, so a device that synced
///   late cannot erase work it never saw.
///
/// No table-level UNIQUE on the natural key (a rule-14 tombstone must be
/// storable); live-row uniqueness is the partial index
/// `ux_daily_scores_natural_key` created in `AppDatabase`.
class DailyScores extends Table with SyncColumns {
  DateTimeColumn get date => dateTime()();
  IntColumn get points => integer().withDefault(const Constant(0))();

  /// How many of the day's widgets were done, out of how many were planned.
  IntColumn get done => integer().withDefault(const Constant(0))();
  IntColumn get planned => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
