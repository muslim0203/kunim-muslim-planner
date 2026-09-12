/// Interpretation of a habit's cadence.
///
/// `core/db/tables/habits_table.dart` gives `Habits` a single free-form
/// text column for this, `frequency` — its own docstring says the exact
/// cadence vocabulary is "still open (`docs/plan.md` §12 phase-2 scope)".
/// This file is what fills that in: [HabitSchedule] is the canonical
/// in-memory model and [HabitSchedule.toJson]/[HabitSchedule.fromJson]
/// define the canonical **JSON string stored in `Habits.frequency`**.
/// (The task brief that named this file also described the storage column
/// as `schedule` with an int `target`; the table that actually exists
/// names them `frequency` (text) and `targetCount` (int) instead — same
/// concepts, different names. `frequency` is used here because it is the
/// only free-form text column `Habits` has and its own doc comment
/// explicitly leaves the vocabulary for this phase to define; nothing in
/// `core/db` needed to change.)
///
/// Canonical JSON shapes (any other shape, and any decode failure, falls
/// back to [HabitSchedule.defaultSchedule] — see [HabitSchedule.fromJson]):
/// ```jsonc
/// {"type": "every_day"}
/// {"type": "specific_weekdays", "weekdays": [1, 3, 5]}   // 1=Mon..7=Sun
/// {"type": "times_per_week", "times": 3}                  // 1..7
/// ```
///
/// This parser is deliberately defensive: `frequency` arrives over sync
/// (another device, possibly a newer app version with schedule shapes this
/// build doesn't know yet) and from the Drift-level column default
/// (`'daily'`, a plain string, not JSON, predating this file). Malformed or
/// unrecognised input must degrade to a sane default and must NEVER throw.
library;

import 'dart:convert';

import 'local_day.dart';

/// The three schedule shapes this phase supports. Unknown wire values
/// decode to [everyDay] (see [HabitSchedule.fromJson]) rather than a
/// fourth "unknown" case, since nothing downstream needs to distinguish
/// "explicitly every day" from "we didn't understand this".
enum HabitScheduleType { everyDay, specificWeekdays, timesPerWeek }

/// A habit's cadence: which days it is due, or (for [HabitScheduleType
/// .timesPerWeek]) how many days a week it is due without fixed days.
class HabitSchedule {
  const HabitSchedule.everyDay()
      : type = HabitScheduleType.everyDay,
        weekdays = const <int>{},
        timesPerWeek = 0;

  /// [weekdays] uses `DateTime.weekday`'s numbering: 1 = Monday .. 7 =
  /// Sunday. An empty set is accepted by the constructor (callers building
  /// one directly are trusted) but [fromJson] never produces one — see its
  /// doc.
  const HabitSchedule.specificWeekdays(this.weekdays)
      : type = HabitScheduleType.specificWeekdays,
        timesPerWeek = 0;

  /// [times] is how many days a week (not which ones) the habit is due,
  /// e.g. "3 times per week". Not clamped by this constructor; [fromJson]
  /// clamps to 1..7 when decoding untrusted input.
  const HabitSchedule.timesPerWeek(int times)
      : type = HabitScheduleType.timesPerWeek,
        weekdays = const <int>{},
        timesPerWeek = times;

  final HabitScheduleType type;
  final Set<int> weekdays;
  final int timesPerWeek;

  /// The fallback for null/empty/unrecognised/malformed input. Chosen over
  /// e.g. "never scheduled" because degrading a habit's cadence to
  /// "every day" is the safer failure mode for a habit tracker — it can
  /// only make a streak too easy to keep, never silently hide a habit the
  /// user is trying to track.
  static const HabitSchedule defaultSchedule = HabitSchedule.everyDay();

  /// Whether this habit is due on [day]. For [HabitScheduleType
  /// .timesPerWeek] every day is "eligible" — there are no fixed days, so
  /// the weekly quota is enforced by `domain/streak.dart` at week
  /// granularity instead of here at day granularity.
  bool isScheduledOn(LocalDay day) {
    switch (type) {
      case HabitScheduleType.everyDay:
        return true;
      case HabitScheduleType.specificWeekdays:
        return weekdays.contains(day.weekday);
      case HabitScheduleType.timesPerWeek:
        return true;
    }
  }

  /// The canonical JSON string to store in `Habits.frequency`.
  String toJson() {
    switch (type) {
      case HabitScheduleType.everyDay:
        return jsonEncode(const {'type': 'every_day'});
      case HabitScheduleType.specificWeekdays:
        final sorted = weekdays.toList()..sort();
        return jsonEncode({'type': 'specific_weekdays', 'weekdays': sorted});
      case HabitScheduleType.timesPerWeek:
        return jsonEncode({'type': 'times_per_week', 'times': timesPerWeek});
    }
  }

  /// Parses `Habits.frequency`. Never throws: anything that isn't exactly
  /// one of the canonical shapes above (including `null`, empty text, the
  /// legacy Drift column default `'daily'`, plain invalid JSON, or JSON
  /// with an unrecognised `type`/out-of-range field) degrades to
  /// [defaultSchedule].
  factory HabitSchedule.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return defaultSchedule;

    // Pre-this-file rows: `Habits.frequency`'s own Drift default is the bare
    // string `'daily'` (not JSON), and its doc comment names `'weekly'` as
    // another plausible free-form value. Both are tolerated explicitly
    // rather than falling through to the JSON decoder, which would throw
    // on non-JSON text and be caught below anyway — this just documents
    // the mapping instead of relying on the catch-all.
    if (raw == 'daily') return const HabitSchedule.everyDay();
    if (raw == 'weekly') return const HabitSchedule.timesPerWeek(1);

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return defaultSchedule;

      switch (decoded['type']) {
        case 'every_day':
          return const HabitSchedule.everyDay();

        case 'specific_weekdays':
          final rawDays = decoded['weekdays'];
          if (rawDays is! List) return defaultSchedule;
          final days = rawDays
              .whereType<num>()
              .map((n) => n.toInt())
              .where((d) => d >= 1 && d <= 7)
              .toSet();
          if (days.isEmpty) return defaultSchedule;
          return HabitSchedule.specificWeekdays(days);

        case 'times_per_week':
          final rawTimes = decoded['times'];
          if (rawTimes is! num) return defaultSchedule;
          final times = rawTimes.toInt().clamp(1, 7);
          return HabitSchedule.timesPerWeek(times);

        default:
          return defaultSchedule;
      }
    } catch (_) {
      // Malformed JSON, wrong field types, etc. — degrade, never throw:
      // this value can arrive from sync or an older app version.
      return defaultSchedule;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is HabitSchedule &&
      other.type == type &&
      other.timesPerWeek == timesPerWeek &&
      _setEquals(other.weekdays, weekdays);

  @override
  int get hashCode => Object.hash(
        type,
        timesPerWeek,
        Object.hashAllUnordered(weekdays),
      );

  @override
  String toString() => 'HabitSchedule(${toJson()})';
}

bool _setEquals(Set<int> a, Set<int> b) {
  if (a.length != b.length) return false;
  return a.every(b.contains);
}
