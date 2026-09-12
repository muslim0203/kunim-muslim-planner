/// A calendar day — year/month/day only, deliberately independent of
/// time-of-day and timezone offset.
///
/// **Timezone rule for the whole habits feature (read this first):** a
/// "day" is always the user's LOCAL calendar day, never a UTC one. A
/// [LocalDay] must be built directly from a local `DateTime`'s
/// `year`/`month`/`day` fields via [LocalDay.fromLocalDateTime] —
/// **never** by calling `.toUtc()` on a local timestamp first. Doing the
/// latter is the classic off-by-one bug: 23:50 local time in a timezone
/// behind UTC (e.g. UTC-8) is already the next calendar day in UTC, so
/// truncating the UTC instant would silently file the completion under
/// the wrong day. Reading the local fields directly never has this
/// problem, regardless of the device's offset.
///
/// `HabitLogs.date` (see `core/db/tables/habits_table.dart`) stores this
/// calendar day's own y/m/d re-expressed as a UTC-midnight instant via
/// [toUtcMidnight] — i.e. the column holds a date tag, not a true instant.
/// [fromUtcMidnight] reverses that for reads. Both directions only ever
/// move y/m/d numbers around; neither performs a real UTC/local
/// conversion, which is precisely what keeps this safe.
class LocalDay implements Comparable<LocalDay> {
  const LocalDay(this.year, this.month, this.day);

  /// Builds a [LocalDay] from a local `DateTime`'s calendar fields. [local]
  /// is expected to be a wall-clock time (`DateTime.now()` or similar);
  /// its `hour`/`minute`/etc. are ignored and it is NOT converted to UTC.
  factory LocalDay.fromLocalDateTime(DateTime local) =>
      LocalDay(local.year, local.month, local.day);

  /// Today, per the device's local clock. Not used by any pure domain
  /// function directly — callers (application/data layers) read this once
  /// and pass it in explicitly, which is what keeps [Streak.compute]
  /// testable without mocking the clock.
  factory LocalDay.now() => LocalDay.fromLocalDateTime(DateTime.now());

  /// Reverses [toUtcMidnight]: rebuilds the [LocalDay] a `HabitLogs.date`
  /// value was written for.
  factory LocalDay.fromUtcMidnight(DateTime utcMidnight) =>
      LocalDay(utcMidnight.year, utcMidnight.month, utcMidnight.day);

  final int year;
  final int month;
  final int day;

  /// The exact value to write to / compare against `HabitLogs.date`.
  DateTime toUtcMidnight() => DateTime.utc(year, month, day);

  /// `DateTime.monday` (1) .. `DateTime.sunday` (7), matching
  /// `HabitSchedule.specificWeekdays`'s vocabulary. Computed via a UTC
  /// `DateTime` purely to sidestep local DST edge cases in date-only
  /// arithmetic — this is not a timezone conversion of a real instant.
  int get weekday => DateTime.utc(year, month, day).weekday;

  /// The Monday (`DateTime.monday`) that starts this day's week, used by
  /// the "N times per week" streak calculation in `domain/streak.dart`.
  LocalDay get mondayOfWeek => addDays(-(weekday - DateTime.monday));

  LocalDay addDays(int delta) {
    final shifted = DateTime.utc(year, month, day).add(Duration(days: delta));
    return LocalDay(shifted.year, shifted.month, shifted.day);
  }

  bool isBefore(LocalDay other) => compareTo(other) < 0;

  bool isAfter(LocalDay other) => compareTo(other) > 0;

  @override
  int compareTo(LocalDay other) =>
      toUtcMidnight().compareTo(other.toUtcMidnight());

  @override
  bool operator ==(Object other) =>
      other is LocalDay &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'LocalDay(${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')})';
}
