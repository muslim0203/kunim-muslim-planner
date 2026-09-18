/// What was planned and what was done, day by day, over a window of days.
///
/// This is the raw material for the daily analysis on the statistics screen
/// and for the points in `daily_score.dart`. Nothing is estimated: a day's
/// items are the widgets scheduled on it, and an item is done when that day's
/// logged amount reaches the widget's daily amount.
///
/// A times-per-week widget has no fixed days, so it is deliberately left out
/// of the daily tallies (the same choice `weekly_stats.dart` makes): counting
/// it every day would show phantom misses on days the user never planned it
/// for.
library;

import '../../habits/domain/habit_schedule.dart';
import '../../habits/domain/local_day.dart';

/// One widget with the history needed to say what it asked for on a day.
class ActivitySource {
  const ActivitySource({
    required this.id,
    required this.title,
    required this.schedule,
    required this.targetCount,
    required this.createdOn,
    required this.countsByDay,
  });

  final String id;
  final String title;
  final HabitSchedule schedule;
  final int targetCount;

  /// Days before this are not counted: a widget cannot be missed before it
  /// existed.
  final LocalDay createdOn;
  final Map<LocalDay, int> countsByDay;

  bool get hasFixedDays => schedule.type != HabitScheduleType.timesPerWeek;

  bool isPlannedOn(LocalDay day) =>
      hasFixedDays && !day.isBefore(createdOn) && schedule.isScheduledOn(day);

  bool isDoneOn(LocalDay day) => (countsByDay[day] ?? 0) >= targetCount;
}

/// One widget's outcome on one day.
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.title,
    required this.done,
  });

  final String id;
  final String title;
  final bool done;
}

class ActivityDay {
  const ActivityDay({required this.day, required this.items});

  final LocalDay day;

  /// Everything planned for the day, done or not.
  final List<ActivityItem> items;

  int get planned => items.length;
  int get done => items.where((item) => item.done).length;
  int get missed => planned - done;

  /// True only when something was planned and all of it was done.
  bool get isComplete => planned > 0 && done == planned;

  /// Nothing was planned: an empty day, never a failed one.
  bool get isFree => planned == 0;

  /// `null` on a free day, so it never reads as 0%.
  double? get ratio => planned == 0 ? null : done / planned;

  /// The widgets that were planned and not done.
  List<ActivityItem> get missedItems => [
        for (final item in items)
          if (!item.done) item
      ];
}

class ActivityHistory {
  const ActivityHistory(this.days);

  /// Oldest day first, ending with today.
  final List<ActivityDay> days;

  ActivityDay? get today => days.isEmpty ? null : days.last;

  /// The [length] days ending with [today].
  static ActivityHistory compute({
    required List<ActivitySource> sources,
    required LocalDay today,
    int length = 30,
  }) {
    final days = <ActivityDay>[];
    for (var offset = length - 1; offset >= 0; offset--) {
      final day = today.addDays(-offset);
      days.add(
        ActivityDay(
          day: day,
          items: [
            for (final source in sources)
              if (source.isPlannedOn(day))
                ActivityItem(
                  id: source.id,
                  title: source.title,
                  done: source.isDoneOn(day),
                ),
          ],
        ),
      );
    }
    return ActivityHistory(days);
  }
}
