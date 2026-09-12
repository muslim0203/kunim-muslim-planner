import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/habits/domain/habit_schedule.dart';
import 'package:kunim/features/habits/domain/local_day.dart';

void main() {
  group('HabitSchedule.fromJson defensive parsing', () {
    test('null/empty degrades to every_day', () {
      expect(HabitSchedule.fromJson(null).type, HabitScheduleType.everyDay);
      expect(HabitSchedule.fromJson('').type, HabitScheduleType.everyDay);
    });

    test('the legacy Drift column default "daily" maps to every_day', () {
      expect(HabitSchedule.fromJson('daily').type, HabitScheduleType.everyDay);
    });

    test('the legacy free-form "weekly" maps to times_per_week(1)', () {
      final schedule = HabitSchedule.fromJson('weekly');
      expect(schedule.type, HabitScheduleType.timesPerWeek);
      expect(schedule.timesPerWeek, 1);
    });

    test('garbage / non-JSON text never throws and degrades to every_day', () {
      expect(
        HabitSchedule.fromJson('not json at all {{{').type,
        HabitScheduleType.everyDay,
      );
    });

    test('a JSON array (not a map) degrades to every_day', () {
      expect(
          HabitSchedule.fromJson('[1,2,3]').type, HabitScheduleType.everyDay);
    });

    test('an unrecognised "type" degrades to every_day', () {
      final schedule = HabitSchedule.fromJson('{"type": "lunar_cycle"}');
      expect(schedule.type, HabitScheduleType.everyDay);
    });

    test('every_day round-trips', () {
      const schedule = HabitSchedule.everyDay();
      final decoded = HabitSchedule.fromJson(schedule.toJson());
      expect(decoded, schedule);
    });

    test('specific_weekdays round-trips and dedupes/sorts', () {
      const schedule = HabitSchedule.specificWeekdays({5, 1, 3});
      final decoded = HabitSchedule.fromJson(schedule.toJson());
      expect(decoded.type, HabitScheduleType.specificWeekdays);
      expect(decoded.weekdays, {1, 3, 5});
    });

    test(
      'specific_weekdays with a non-list "weekdays" degrades to every_day',
      () {
        final schedule = HabitSchedule.fromJson(
          '{"type": "specific_weekdays", "weekdays": "monday"}',
        );
        expect(schedule.type, HabitScheduleType.everyDay);
      },
    );

    test(
      'specific_weekdays with out-of-range/empty weekdays degrades to every_day',
      () {
        final schedule = HabitSchedule.fromJson(
          '{"type": "specific_weekdays", "weekdays": [0, 8, 9]}',
        );
        expect(schedule.type, HabitScheduleType.everyDay);
      },
    );

    test('times_per_week round-trips', () {
      const schedule = HabitSchedule.timesPerWeek(3);
      final decoded = HabitSchedule.fromJson(schedule.toJson());
      expect(decoded.type, HabitScheduleType.timesPerWeek);
      expect(decoded.timesPerWeek, 3);
    });

    test('times_per_week clamps an out-of-range "times" into 1..7', () {
      final tooHigh = HabitSchedule.fromJson(
        '{"type": "times_per_week", "times": 99}',
      );
      expect(tooHigh.timesPerWeek, 7);

      final tooLow = HabitSchedule.fromJson(
        '{"type": "times_per_week", "times": -5}',
      );
      expect(tooLow.timesPerWeek, 1);
    });

    test('times_per_week with a non-numeric "times" degrades to every_day', () {
      final schedule = HabitSchedule.fromJson(
        '{"type": "times_per_week", "times": "three"}',
      );
      expect(schedule.type, HabitScheduleType.everyDay);
    });
  });

  group('HabitSchedule.isScheduledOn', () {
    test('every_day is due every day', () {
      const schedule = HabitSchedule.everyDay();
      for (var d = 1; d <= 7; d++) {
        expect(schedule.isScheduledOn(LocalDay(2026, 9, d)), isTrue);
      }
    });

    test('specific_weekdays is due only on the listed ISO weekdays', () {
      // 2026-09-07 is a Monday.
      const schedule = HabitSchedule.specificWeekdays({
        DateTime.monday,
        DateTime.wednesday,
        DateTime.friday,
      });
      expect(schedule.isScheduledOn(const LocalDay(2026, 9, 7)), isTrue); // Mon
      expect(
          schedule.isScheduledOn(const LocalDay(2026, 9, 8)), isFalse); // Tue
      expect(schedule.isScheduledOn(const LocalDay(2026, 9, 9)), isTrue); // Wed
      expect(
        schedule.isScheduledOn(const LocalDay(2026, 9, 12)),
        isFalse,
      ); // Sat
    });

    test(
        'times_per_week is "eligible" every day (weekly quota is enforced '
        'in domain/streak.dart, not here)', () {
      const schedule = HabitSchedule.timesPerWeek(3);
      expect(schedule.isScheduledOn(const LocalDay(2026, 9, 12)), isTrue);
      expect(schedule.isScheduledOn(const LocalDay(2026, 9, 13)), isTrue);
    });
  });
}
