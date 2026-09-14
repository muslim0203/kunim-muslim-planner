import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/stats/domain/wellbeing_week.dart';

/// Monday, 14 September 2026.
const _today = LocalDay(2026, 9, 14);
final _stamp = DateTime.utc(2026, 9, 14, 8);

MoodLog _mood(int dayOffset, int score, {bool deleted = false}) => MoodLog(
      id: 'm$dayOffset$score',
      userId: null,
      createdAt: _stamp,
      updatedAt: _stamp,
      deletedAt: deleted ? _stamp : null,
      serverVersion: 0,
      dirty: false,
      refId: null,
      date: _today.addDays(dayOffset).toUtcMidnight(),
      score: score,
      tags: '[]',
      note: null,
    );

SleepLog _sleep(int dayOffset, int minutes, {int? quality}) => SleepLog(
      id: 's$dayOffset',
      userId: null,
      createdAt: _stamp,
      updatedAt: _stamp,
      deletedAt: null,
      serverVersion: 0,
      dirty: false,
      refId: null,
      date: _today.addDays(dayOffset).toUtcMidnight(),
      bedTime: _stamp.subtract(Duration(minutes: minutes)),
      wakeTime: _stamp,
      durationMin: minutes,
      quality: quality,
      note: null,
    );

HealthLog _health(
  int dayOffset, {
  int? waterMl,
  int? steps,
  int? workoutMin,
}) =>
    HealthLog(
      id: 'h$dayOffset',
      userId: null,
      createdAt: _stamp,
      updatedAt: _stamp,
      deletedAt: null,
      serverVersion: 0,
      dirty: false,
      refId: null,
      date: _today.addDays(dayOffset).toUtcMidnight(),
      waterMl: waterMl,
      steps: steps,
      workoutMin: workoutMin,
      calories: null,
      weightKg: null,
      note: null,
    );

FamilyLog _family(int dayOffset, {int? minutes}) => FamilyLog(
      id: 'f$dayOffset',
      userId: null,
      createdAt: _stamp,
      updatedAt: _stamp,
      deletedAt: null,
      serverVersion: 0,
      dirty: false,
      refId: null,
      date: _today.addDays(dayOffset).toUtcMidnight(),
      minutes: minutes,
      activities: '["walk"]',
      note: null,
    );

WellbeingWeek _compute({
  List<MoodLog> moods = const [],
  List<SleepLog> sleeps = const [],
  List<HealthLog> healths = const [],
  List<FamilyLog> families = const [],
}) =>
    WellbeingWeek.compute(
      moods: moods,
      sleeps: sleeps,
      healths: healths,
      families: families,
      today: _today,
    );

void main() {
  test('nothing recorded gives counts of zero and no averages', () {
    final week = _compute();

    expect(week.hasAny, isFalse);
    expect(week.moodAverage, isNull);
    expect(week.sleepAverageMin, isNull);
    expect(week.waterAverageMl, isNull);
    expect(week.familyTotalMin, isNull);
  });

  test('only live entries from the last seven days count', () {
    final week = _compute(
      moods: [
        _mood(0, 5),
        _mood(-6, 4),
        _mood(-7, 1), // last week
        _mood(-2, 2, deleted: true),
      ],
    );

    expect(week.moodDays, 2);
    expect(week.moodAverage, 4.5);
  });

  test('averages use only the days that have the value', () {
    final week = _compute(
      sleeps: [_sleep(0, 480, quality: 4), _sleep(-1, 420)],
      healths: [
        _health(0, waterMl: 1000, workoutMin: 30),
        _health(-1, steps: 6000, workoutMin: 20),
      ],
      families: [_family(0, minutes: 60), _family(-3)],
    );

    expect(week.sleepNights, 2);
    expect(week.sleepAverageMin, 450);
    expect(week.sleepQualityAverage, 4.0);

    expect(week.healthDays, 2);
    expect(week.waterAverageMl, 1000);
    expect(week.stepsAverage, 6000);
    expect(week.workoutTotalMin, 50);

    expect(week.familyDays, 2);
    expect(week.familyTotalMin, 60);
    expect(week.hasAny, isTrue);
  });
}
