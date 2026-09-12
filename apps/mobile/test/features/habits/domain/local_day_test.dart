import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/habits/domain/local_day.dart';

void main() {
  group('LocalDay timezone rule', () {
    test(
      'a local timestamp near midnight keeps its own calendar day — the '
      'day is read from year/month/day directly, never via .toUtc()',
      () {
        // Two local timestamps on the SAME calendar day, one just after
        // midnight and one just before the next one, must produce the
        // SAME LocalDay. A `.toUtc()`-based implementation could split
        // these into two different days depending on the host's offset;
        // reading the fields directly never can.
        final justAfterMidnight = DateTime(2026, 9, 5, 0, 1);
        final justBeforeNextMidnight = DateTime(2026, 9, 5, 23, 59);

        expect(
          LocalDay.fromLocalDateTime(justAfterMidnight),
          const LocalDay(2026, 9, 5),
        );
        expect(
          LocalDay.fromLocalDateTime(justBeforeNextMidnight),
          const LocalDay(2026, 9, 5),
        );
      },
    );

    test(
      'toUtcMidnight() re-expresses the calendar day as UTC midnight, not '
      'the source instant converted to UTC and truncated',
      () {
        final lateEvening = DateTime(2026, 9, 5, 23, 59, 59);
        final day = LocalDay.fromLocalDateTime(lateEvening);

        // Whatever the host's timezone offset is, the stored value is
        // exactly midnight UTC on the SAME y/m/d as the local timestamp —
        // never `lateEvening.toUtc()` truncated to a day, which (in a
        // timezone behind UTC) could already be the next calendar day.
        expect(day.toUtcMidnight(), DateTime.utc(2026, 9, 5));
      },
    );

    test('fromUtcMidnight reverses toUtcMidnight', () {
      const day = LocalDay(2026, 12, 31);
      expect(LocalDay.fromUtcMidnight(day.toUtcMidnight()), day);
    });
  });

  group('LocalDay arithmetic', () {
    test('addDays crosses month/year boundaries correctly', () {
      expect(
        const LocalDay(2026, 12, 31).addDays(1),
        const LocalDay(2027, 1, 1),
      );
      expect(
        const LocalDay(2026, 3, 1).addDays(-1),
        const LocalDay(2026, 2, 28),
      );
    });

    test('weekday matches DateTime.weekday numbering (1=Mon..7=Sun)', () {
      // 2026-09-07 is a Monday (verified against the system calendar).
      expect(const LocalDay(2026, 9, 7).weekday, DateTime.monday);
      expect(const LocalDay(2026, 9, 13).weekday, DateTime.sunday);
    });

    test('mondayOfWeek finds the Monday that starts the week', () {
      expect(
        const LocalDay(2026, 9, 10).mondayOfWeek, // Thursday
        const LocalDay(2026, 9, 7),
      );
      expect(
        const LocalDay(2026, 9, 13).mondayOfWeek, // Sunday
        const LocalDay(2026, 9, 7),
      );
      expect(
        const LocalDay(2026, 9, 7).mondayOfWeek, // Monday itself
        const LocalDay(2026, 9, 7),
      );
    });

    test('compareTo / isBefore / isAfter order by calendar date', () {
      const a = LocalDay(2026, 9, 1);
      const b = LocalDay(2026, 9, 2);
      expect(a.isBefore(b), isTrue);
      expect(b.isAfter(a), isTrue);
      expect(a.compareTo(a), 0);
    });
  });
}
