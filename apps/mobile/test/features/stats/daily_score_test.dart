// The daily analysis (what was planned, what was missed) and the points it
// earns.
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/habits/domain/habit_schedule.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/stats/domain/activity_history.dart';
import 'package:kunim/features/stats/domain/daily_score.dart';

const _today = LocalDay(2026, 9, 18);
const _start = LocalDay(2026, 9, 1);

ActivitySource _daily(
  String id, {
  Map<LocalDay, int> counts = const {},
  int target = 1,
  LocalDay createdOn = _start,
}) {
  return ActivitySource(
    id: id,
    title: id,
    schedule: const HabitSchedule.everyDay(),
    targetCount: target,
    createdOn: createdOn,
    countsByDay: counts,
  );
}

void main() {
  group('history', () {
    test('a day lists every widget planned on it, done or missed', () {
      final history = ActivityHistory.compute(
        sources: [
          _daily('kitob', counts: {_today: 1}),
          _daily('sport'),
        ],
        today: _today,
        length: 1,
      );

      final day = history.today!;
      expect(day.planned, 2);
      expect(day.done, 1);
      expect(day.missed, 1);
      expect(day.missedItems.single.id, 'sport');
      expect(day.isComplete, isFalse);
      expect(day.ratio, 0.5);
    });

    test('a widget is not missed before it existed', () {
      final history = ActivityHistory.compute(
        sources: [_daily('kitob', createdOn: _today)],
        today: _today,
        length: 3,
      );

      expect(history.days.map((d) => d.planned), [0, 0, 1]);
      expect(history.days.first.isFree, isTrue);
    });

    test('a times-per-week widget stays out of the daily tallies', () {
      final history = ActivityHistory.compute(
        sources: [
          ActivitySource(
            id: 'sport',
            title: 'sport',
            schedule: const HabitSchedule.timesPerWeek(3),
            targetCount: 1,
            createdOn: _start,
            countsByDay: const {},
          ),
        ],
        today: _today,
        length: 3,
      );

      expect(history.days.every((day) => day.isFree), isTrue);
    });

    test('a widget with a daily amount needs the whole amount', () {
      final history = ActivityHistory.compute(
        sources: [
          _daily('kitob', target: 10, counts: {_today: 4}),
        ],
        today: _today,
        length: 1,
      );

      expect(history.today!.done, 0);
    });
  });

  group('points', () {
    test('each widget done earns points, all of them earn a bonus', () {
      final history = ActivityHistory.compute(
        sources: [
          _daily('kitob', counts: {_today: 1}),
          _daily('sport', counts: {_today: 1}),
        ],
        today: _today,
        length: 1,
      );

      final board = ScoreBoard.compute(history);

      // Two widgets done (20) + everything done (20) + first day of the run (5).
      expect(board.todayPoints, 45);
      expect(board.streak, 1);
    });

    test('a partial day earns only what was done', () {
      final history = ActivityHistory.compute(
        sources: [
          _daily('kitob', counts: {_today: 1}),
          _daily('sport')
        ],
        today: _today,
        length: 1,
      );

      final board = ScoreBoard.compute(history);

      expect(board.todayPoints, 10);
      expect(board.streak, 0);
    });

    test('a run of complete days pays more each day, up to the cap', () {
      final counts = {
        for (var offset = 0; offset < 15; offset++) _today.addDays(-offset): 1,
      };
      final history = ActivityHistory.compute(
        sources: [_daily('kitob', counts: counts)],
        today: _today,
        length: 15,
      );

      final board = ScoreBoard.compute(history);

      expect(board.days.first.points, 10 + 20 + 5);
      // Day 10 onwards the streak bonus stops growing at 50.
      expect(board.days.last.points, 10 + 20 + 50);
      expect(board.streak, 15);
      expect(board.bestStreak, 15);
    });

    test('a free day keeps a run alive, a missed day breaks it', () {
      // Created today-1 so the first day of the window has nothing planned.
      final source = _daily(
        'kitob',
        createdOn: _today.addDays(-1),
        counts: {_today.addDays(-1): 1},
      );
      final history = ActivityHistory.compute(
        sources: [source],
        today: _today,
        length: 3,
      );

      final board = ScoreBoard.compute(history);

      expect(board.days.map((day) => day.streak), [0, 1, 0]);
      expect(board.todayPoints, 0);
    });

    test('levels come from the points, with the rest still to earn', () {
      final counts = {
        for (var offset = 0; offset < 20; offset++) _today.addDays(-offset): 1,
      };
      final board = ScoreBoard.compute(
        ActivityHistory.compute(
          sources: [_daily('kitob', counts: counts)],
          today: _today,
          length: 20,
        ),
      );

      expect(board.total, greaterThan(0));
      expect(board.level, board.total ~/ ScoreBoard.pointsPerLevel + 1);
      expect(
        board.pointsToNextLevel,
        board.level * ScoreBoard.pointsPerLevel - board.total,
      );
      expect(board.lastWeek, lessThanOrEqualTo(board.total));
    });
  });
}
