/// Points for the day's work, and the level they add up to.
///
/// The rules are deliberately few, so a user can predict their score without
/// reading a table:
///
/// - every widget done on the day: [pointsPerItem];
/// - everything the day asked for done: [allDoneBonus] on top;
/// - a run of such days: [streakBonusPerDay] for each day of the run,
///   counting the day itself, capped at [streakBonusCap].
///
/// A day with nothing planned scores nothing and does not break a run — it is
/// free time, not a failure.
library;

import '../../habits/domain/local_day.dart';
import 'activity_history.dart';

class DailyScore {
  const DailyScore({
    required this.day,
    required this.done,
    required this.planned,
    required this.streak,
    required this.points,
  });

  final LocalDay day;
  final int done;
  final int planned;

  /// Complete days in a row ending on this one, 0 when the day is not
  /// complete.
  final int streak;
  final int points;

  bool get isComplete => planned > 0 && done == planned;
}

class ScoreBoard {
  const ScoreBoard({required this.days});

  /// Oldest day first, one entry per day of the history.
  final List<DailyScore> days;

  static const int pointsPerItem = 10;
  static const int allDoneBonus = 20;
  static const int streakBonusPerDay = 5;
  static const int streakBonusCap = 50;

  /// Points that make up one level.
  static const int pointsPerLevel = 500;

  int get total => days.fold(0, (sum, day) => sum + day.points);

  int get todayPoints => days.isEmpty ? 0 : days.last.points;

  /// Points over the last seven days of the history.
  int get lastWeek {
    final window = days.length <= 7 ? days : days.sublist(days.length - 7);
    return window.fold(0, (sum, day) => sum + day.points);
  }

  /// Complete days in a row ending today (a free day keeps a run alive
  /// without extending it).
  int get streak => days.isEmpty ? 0 : days.last.streak;

  /// The longest run of complete days anywhere in the history.
  int get bestStreak =>
      days.fold(0, (best, day) => day.streak > best ? day.streak : best);

  int get level => total ~/ pointsPerLevel + 1;

  /// Points still needed for the next level.
  int get pointsToNextLevel => level * pointsPerLevel - total;

  static ScoreBoard compute(ActivityHistory history) {
    final scores = <DailyScore>[];
    var streak = 0;
    for (final day in history.days) {
      if (day.isComplete) {
        streak += 1;
      } else if (!day.isFree) {
        streak = 0;
      }
      scores.add(
        DailyScore(
          day: day.day,
          done: day.done,
          planned: day.planned,
          streak: day.isComplete ? streak : 0,
          points: _pointsFor(day, streak),
        ),
      );
    }
    return ScoreBoard(days: scores);
  }

  static int _pointsFor(ActivityDay day, int streak) {
    if (day.done == 0) return 0;
    var points = day.done * pointsPerItem;
    if (day.isComplete) {
      points += allDoneBonus;
      final bonus = streak * streakBonusPerDay;
      points += bonus > streakBonusCap ? streakBonusCap : bonus;
    }
    return points;
  }
}
