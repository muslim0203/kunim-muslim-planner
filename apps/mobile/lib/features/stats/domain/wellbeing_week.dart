/// This week's mood, sleep, health and family numbers, computed only from
/// entries the user actually recorded.
///
/// Averages use the days that have a value, never all seven: a day without
/// an entry is "not recorded", not zero. Nothing is inferred, scored or
/// interpreted here.
library;

import 'package:kunim/core/db/app_database.dart';

import '../../habits/domain/local_day.dart';

class WellbeingWeek {
  const WellbeingWeek({
    required this.moodDays,
    required this.moodAverage,
    required this.sleepNights,
    required this.sleepAverageMin,
    required this.sleepQualityAverage,
    required this.healthDays,
    required this.waterAverageMl,
    required this.stepsAverage,
    required this.workoutTotalMin,
    required this.familyDays,
    required this.familyTotalMin,
  });

  final int moodDays;

  /// Mean 1-5 score, or `null` without entries.
  final double? moodAverage;

  final int sleepNights;
  final int? sleepAverageMin;

  /// Mean 1-5 quality over the nights that were rated.
  final double? sleepQualityAverage;

  final int healthDays;
  final int? waterAverageMl;
  final int? stepsAverage;
  final int? workoutTotalMin;

  final int familyDays;
  final int? familyTotalMin;

  bool get hasAny => moodDays + sleepNights + healthDays + familyDays > 0;

  /// The seven local days ending with [today].
  static WellbeingWeek compute({
    required List<MoodLog> moods,
    required List<SleepLog> sleeps,
    required List<HealthLog> healths,
    required List<FamilyLog> families,
    required LocalDay today,
  }) {
    final firstDay = today.addDays(-6);
    bool inWeek(DateTime dateTag, DateTime? deletedAt) {
      if (deletedAt != null) return false;
      final day = LocalDay.fromUtcMidnight(dateTag);
      return !day.isBefore(firstDay) && !day.isAfter(today);
    }

    final weekMoods = [
      for (final log in moods)
        if (inWeek(log.date, log.deletedAt)) log,
    ];
    final weekSleeps = [
      for (final log in sleeps)
        if (inWeek(log.date, log.deletedAt)) log,
    ];
    final weekHealth = [
      for (final log in healths)
        if (inWeek(log.date, log.deletedAt)) log,
    ];
    final weekFamily = [
      for (final log in families)
        if (inWeek(log.date, log.deletedAt)) log,
    ];

    return WellbeingWeek(
      moodDays: weekMoods.length,
      moodAverage: _average(weekMoods.map((log) => log.score)),
      sleepNights: weekSleeps.length,
      sleepAverageMin:
          _average(weekSleeps.map((log) => log.durationMin))?.round(),
      sleepQualityAverage:
          _average(weekSleeps.map((log) => log.quality).whereType<int>()),
      healthDays: weekHealth.length,
      waterAverageMl:
          _average(weekHealth.map((log) => log.waterMl).whereType<int>())
              ?.round(),
      stepsAverage:
          _average(weekHealth.map((log) => log.steps).whereType<int>())
              ?.round(),
      workoutTotalMin:
          _sum(weekHealth.map((log) => log.workoutMin).whereType<int>()),
      familyDays: weekFamily.length,
      familyTotalMin:
          _sum(weekFamily.map((log) => log.minutes).whereType<int>()),
    );
  }

  static double? _average(Iterable<int> values) {
    final list = values.toList();
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a + b) / list.length;
  }

  static int? _sum(Iterable<int> values) {
    final list = values.toList();
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a + b);
  }
}
