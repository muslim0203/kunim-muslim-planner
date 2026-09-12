import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/habits/domain/habit_schedule.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/habits/domain/streak.dart';

void main() {
  group('day-granular streak (everyDay / specificWeekdays)', () {
    test(
      'a weekday-only schedule skips weekends without breaking the streak',
      () {
        // Friday 2026-09-11. Every Mon-Fri day from 2026-08-28 through
        // 2026-09-11 (inclusive) is logged as completed; weekends in that
        // range are deliberately left out of completedDays entirely
        // (nothing logs on an off day) to prove they don't need to.
        const today = LocalDay(2026, 9, 11);
        const schedule = HabitSchedule.specificWeekdays({
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
        });

        var expectedWeekdayCount = 0;
        final completedDays = <LocalDay>{};
        var cursor = today;
        for (var i = 0; i < 15; i++) {
          if (cursor.weekday <= DateTime.friday) {
            completedDays.add(cursor);
            expectedWeekdayCount++;
          }
          cursor = cursor.addDays(-1);
        }
        // Sanity check on the fixture itself, independent of Streak.
        expect(expectedWeekdayCount, 11); // 15 calendar days -> 11 weekdays

        final result = Streak.compute(
          schedule: schedule,
          completedDays: completedDays,
          today: today,
        );

        expect(result.unit, StreakUnit.day);
        expect(result.current, expectedWeekdayCount);
      },
    );

    test('a genuine missed scheduled day resets the streak to zero', () {
      const today = LocalDay(2026, 9, 12);
      const schedule = HabitSchedule.everyDay();

      // Plenty of completions further back, but yesterday (a scheduled
      // day, since every_day) is missing and today is not done yet.
      final completedDays = <LocalDay>{
        today.addDays(-5),
        today.addDays(-4),
        today.addDays(-3),
        // today.addDays(-2): also intentionally missing
        // today.addDays(-1): the actual break — missing
      };

      final result = Streak.compute(
        schedule: schedule,
        completedDays: completedDays,
        today: today,
      );

      expect(result.current, 0);
      expect(result.badges, isEmpty);
    });

    test(
      'an in-progress (not yet completed) today does not break a run',
      () {
        const today = LocalDay(2026, 9, 12);
        const schedule = HabitSchedule.everyDay();

        // Seven consecutive prior days completed; today is scheduled but
        // NOT in completedDays (still "in progress").
        final completedDays = <LocalDay>{
          for (var i = 1; i <= 7; i++) today.addDays(-i),
        };

        final result = Streak.compute(
          schedule: schedule,
          completedDays: completedDays,
          today: today,
        );

        expect(
          result.current,
          7,
          reason: 'an unfinished today must not show the streak as broken',
        );
        expect(result.badges, {StreakBadge.sevenStreak});
      },
    );

    test('completing today too simply extends the same streak by one', () {
      const today = LocalDay(2026, 9, 12);
      const schedule = HabitSchedule.everyDay();

      final completedDays = <LocalDay>{
        today,
        for (var i = 1; i <= 7; i++) today.addDays(-i),
      };

      final result = Streak.compute(
        schedule: schedule,
        completedDays: completedDays,
        today: today,
      );

      expect(result.current, 8);
    });

    test('a habit with zero completions has a zero streak and no badges', () {
      const today = LocalDay(2026, 9, 12);
      const schedule = HabitSchedule.everyDay();

      final result = Streak.compute(
        schedule: schedule,
        completedDays: const {},
        today: today,
      );

      expect(result.current, 0);
      expect(result.badges, isEmpty);
    });

    test(
      'a specificWeekdays schedule with no weekdays selected terminates '
      '(safety bound) instead of looping forever',
      () {
        const today = LocalDay(2026, 9, 12);
        const schedule = HabitSchedule.specificWeekdays(<int>{});

        final result = Streak.compute(
          schedule: schedule,
          completedDays: const {},
          today: today,
        );

        expect(result.current, 0);
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    group('7 / 30 / 100 badge thresholds', () {
      StreakResult streakOfLength(int n) {
        const today = LocalDay(2026, 9, 12);
        const schedule = HabitSchedule.everyDay();
        // today left uncompleted (in progress) so `current` == n exactly.
        final completedDays = <LocalDay>{
          for (var i = 1; i <= n; i++) today.addDays(-i),
        };
        return Streak.compute(
          schedule: schedule,
          completedDays: completedDays,
          today: today,
        );
      }

      test('6 does not earn the 7-badge', () {
        final r = streakOfLength(6);
        expect(r.current, 6);
        expect(r.badges, isEmpty);
      });

      test('exactly 7 earns the 7-badge', () {
        final r = streakOfLength(7);
        expect(r.current, 7);
        expect(r.badges, {StreakBadge.sevenStreak});
      });

      test('29 earns only the 7-badge, not the 30-badge', () {
        final r = streakOfLength(29);
        expect(r.badges, {StreakBadge.sevenStreak});
      });

      test('exactly 30 earns the 7- and 30-badges', () {
        final r = streakOfLength(30);
        expect(r.badges, {StreakBadge.sevenStreak, StreakBadge.thirtyStreak});
      });

      test('99 does not earn the 100-badge', () {
        final r = streakOfLength(99);
        expect(r.badges, {StreakBadge.sevenStreak, StreakBadge.thirtyStreak});
      });

      test('exactly 100 earns all three badges', () {
        final r = streakOfLength(100);
        expect(r.badges, {
          StreakBadge.sevenStreak,
          StreakBadge.thirtyStreak,
          StreakBadge.hundredStreak,
        });
      });
    });
  });

  group('week-granular streak (timesPerWeek)', () {
    test('a fully-elapsed past week that missed quota breaks the streak', () {
      const today = LocalDay(2026, 9, 10); // Thursday, mid-week
      const schedule = HabitSchedule.timesPerWeek(3);
      final thisMonday = today.mondayOfWeek; // 2026-09-07

      final completedDays = <LocalDay>{
        // This week: 2 completions so far (below quota, but still
        // in-progress since the week isn't over).
        thisMonday,
        thisMonday.addDays(1),
        // Last week: only 1 completion (below quota, and that week IS
        // fully over) -> a genuine break.
        thisMonday.addDays(-7),
      };

      final result = Streak.compute(
        schedule: schedule,
        completedDays: completedDays,
        today: today,
      );

      expect(result.unit, StreakUnit.week);
      expect(
        result.current,
        0,
        reason: 'the current week is still in progress (2 < 3, not yet a '
            'miss); last week is fully over and only had 1 < 3',
      );
    });

    test('consecutive past weeks meeting quota build a week streak', () {
      const today = LocalDay(2026, 9, 10); // Thursday
      const schedule = HabitSchedule.timesPerWeek(2);
      final thisMonday = today.mondayOfWeek;

      final completedDays = <LocalDay>{
        // This week: quota already met (2 of 2), still counts even though
        // the week isn't over.
        thisMonday,
        thisMonday.addDays(1),
        // Previous 2 full weeks: quota met each time.
        thisMonday.addDays(-7),
        thisMonday.addDays(-6),
        thisMonday.addDays(-14),
        thisMonday.addDays(-13),
      };

      final result = Streak.compute(
        schedule: schedule,
        completedDays: completedDays,
        today: today,
      );

      expect(result.unit, StreakUnit.week);
      expect(result.current, 3);
    });
  });
}
