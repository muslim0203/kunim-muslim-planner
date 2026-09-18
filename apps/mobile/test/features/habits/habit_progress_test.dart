// A widget's progress towards its total and the day it would finish on.
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/habits/domain/habit_progress.dart';
import 'package:kunim/features/habits/domain/local_day.dart';

const _today = LocalDay(2026, 9, 18);

void main() {
  test('an open-ended widget has no total to measure against', () {
    const progress = HabitProgress(done: 40, total: null, perDay: 10);

    expect(progress.remaining, isNull);
    expect(progress.ratio, isNull);
    expect(progress.daysLeft, isNull);
    expect(progress.finishDay(_today), isNull);
  });

  test('a book counts down its pages and projects the finish day', () {
    // 300 pages, 120 read, 10 a day: 18 days left, today included.
    const progress = HabitProgress(done: 120, total: 300, perDay: 10);

    expect(progress.remaining, 180);
    expect(progress.ratio, closeTo(0.4, 0.0001));
    expect(progress.daysLeft, 18);
    expect(progress.finishDay(_today), const LocalDay(2026, 10, 5));
  });

  test('a part day still counts as a whole day', () {
    const progress = HabitProgress(done: 0, total: 25, perDay: 10);

    expect(progress.daysLeft, 3);
  });

  test('a finished widget stops at zero and finishes today', () {
    const progress = HabitProgress(done: 320, total: 300, perDay: 10);

    expect(progress.remaining, 0);
    expect(progress.ratio, 1);
    expect(progress.isFinished, isTrue);
    expect(progress.daysLeft, 0);
    expect(progress.finishDay(_today), _today);
  });

  test('without a daily amount there is nothing to project', () {
    const progress = HabitProgress(done: 10, total: 300, perDay: 0);

    expect(progress.remaining, 290);
    expect(progress.daysLeft, isNull);
    expect(progress.finishDay(_today), isNull);
  });
}
