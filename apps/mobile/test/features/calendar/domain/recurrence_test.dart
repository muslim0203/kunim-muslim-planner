// Recurrence-domain tests for the kalendar RRULE subset (`docs/plan.md`
// §12 phase-2 DoD) — see `lib/features/calendar/domain/recurrence.dart`
// for the exact subset and the rules chosen for the awkward cases this
// file exercises.
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/calendar/domain/recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

DateTime utc(int y, int m, int d, [int h = 0, int min = 0, int s = 0]) =>
    DateTime.utc(y, m, d, h, min, s);

/// Builds a minimal [CalendarEvent] row for `expandEventOccurrences`
/// tests — only the fields recurrence expansion actually reads matter.
CalendarEvent _event({
  required DateTime startAt,
  DateTime? endAt,
  String? rrule,
}) {
  return CalendarEvent(
    id: 'evt-1',
    userId: null,
    createdAt: startAt,
    updatedAt: startAt,
    deletedAt: null,
    serverVersion: 0,
    dirty: true,
    title: 'Test event',
    description: null,
    startAt: startAt,
    endAt: endAt,
    allDay: false,
    rrule: rrule,
    location: null,
  );
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('no rrule / degrade to single occurrence', () {
    test('null rrule yields exactly the start time if it is in range', () {
      final dtstart = utc(2026, 9, 10, 9);
      final result = expandRruleOccurrences(
        rrule: null,
        dtstart: dtstart,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 9, 30),
      );
      expect(result, [dtstart]);
    });

    test('null rrule yields nothing when the start time is outside the range',
        () {
      final dtstart = utc(2026, 9, 10, 9);
      final result = expandRruleOccurrences(
        rrule: null,
        dtstart: dtstart,
        rangeStart: utc(2026, 10, 1),
        rangeEnd: utc(2026, 10, 30),
      );
      expect(result, isEmpty);
    });

    test('empty-string rrule degrades the same as null', () {
      final dtstart = utc(2026, 9, 10, 9);
      final result = expandRruleOccurrences(
        rrule: '   ',
        dtstart: dtstart,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 9, 30),
      );
      expect(result, [dtstart]);
    });

    test('an unknown FREQ never throws and degrades to a single occurrence',
        () {
      final dtstart = utc(2026, 9, 10, 9);
      expect(
        () => expandRruleOccurrences(
          rrule: 'FREQ=YEARLY',
          dtstart: dtstart,
          rangeStart: utc(2026, 1, 1),
          rangeEnd: utc(2027, 12, 31),
        ),
        returnsNormally,
      );
      final result = expandRruleOccurrences(
        rrule: 'FREQ=YEARLY',
        dtstart: dtstart,
        rangeStart: utc(2026, 1, 1),
        rangeEnd: utc(2027, 12, 31),
      );
      expect(result, [dtstart]);
    });

    test(
        'a totally malformed string never throws and degrades to a single occurrence',
        () {
      final dtstart = utc(2026, 9, 10, 9);
      expect(
        () => expandRruleOccurrences(
          rrule: 'this is not an rrule at all',
          dtstart: dtstart,
          rangeStart: utc(2026, 1, 1),
          rangeEnd: utc(2027, 12, 31),
        ),
        returnsNormally,
      );
      final result = expandRruleOccurrences(
        rrule: 'not-a-key-value-pair-either;;FREQ',
        dtstart: dtstart,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 9, 30),
      );
      expect(result, [dtstart]);
    });

    test('an unsupported RRULE part (e.g. BYMONTHDAY) degrades the whole rule',
        () {
      final dtstart = utc(2026, 9, 10, 9);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=MONTHLY;BYMONTHDAY=10',
        dtstart: dtstart,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 12, 31),
      );
      expect(result, [dtstart]);
    });

    test('BYDAY combined with a non-WEEKLY FREQ is unsupported and degrades',
        () {
      final dtstart = utc(2026, 9, 10, 9);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=MONTHLY;BYDAY=MO',
        dtstart: dtstart,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 12, 31),
      );
      expect(result, [dtstart]);
    });

    test('a numbered BYDAY prefix (e.g. 2MO) is unsupported and degrades', () {
      final dtstart = utc(2026, 9, 10, 9);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=WEEKLY;BYDAY=2MO',
        dtstart: dtstart,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 12, 31),
      );
      expect(result, [dtstart]);
    });
  });

  group('FREQ=DAILY', () {
    test('without INTERVAL recurs every day', () {
      final dtstart = utc(2026, 9, 1, 9);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=DAILY',
        dtstart: dtstart,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 9, 5, 23, 59, 59),
      );
      expect(result, [
        utc(2026, 9, 1, 9),
        utc(2026, 9, 2, 9),
        utc(2026, 9, 3, 9),
        utc(2026, 9, 4, 9),
        utc(2026, 9, 5, 9),
      ]);
    });

    test('with INTERVAL=2 skips every other day', () {
      final dtstart = utc(2026, 9, 1, 9);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=DAILY;INTERVAL=2',
        dtstart: dtstart,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 9, 7, 23, 59, 59),
      );
      expect(result, [
        utc(2026, 9, 1, 9),
        utc(2026, 9, 3, 9),
        utc(2026, 9, 5, 9),
        utc(2026, 9, 7, 9),
      ]);
    });
  });

  group('FREQ=WEEKLY', () {
    test('without BYDAY recurs on the same weekday as dtstart', () {
      // 2026-09-02 is a Wednesday.
      final dtstart = utc(2026, 9, 2, 8);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=WEEKLY',
        dtstart: dtstart,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 9, 30, 23, 59),
      );
      expect(result, [
        utc(2026, 9, 2, 8),
        utc(2026, 9, 9, 8),
        utc(2026, 9, 16, 8),
        utc(2026, 9, 23, 8),
        utc(2026, 9, 30, 8),
      ]);
    });

    test('with INTERVAL=2 recurs every other week', () {
      final dtstart = utc(2026, 9, 2, 8); // Wednesday
      final result = expandRruleOccurrences(
        rrule: 'FREQ=WEEKLY;INTERVAL=2',
        dtstart: dtstart,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 9, 30, 23, 59),
      );
      expect(result, [
        utc(2026, 9, 2, 8),
        utc(2026, 9, 16, 8),
        utc(2026, 9, 30, 8),
      ]);
    });

    test(
        'BYDAY across a week boundary produces occurrences on different weekdays',
        () {
      // 2026-09-04 is a Friday. BYDAY=MO,FR: the Monday of dtstart's own
      // week is before dtstart so it's excluded; the following Monday
      // (the next calendar week) IS included — that Friday -> Monday gap
      // crosses the week boundary.
      final dtstart = utc(2026, 9, 4, 7);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=WEEKLY;BYDAY=MO,FR',
        dtstart: dtstart,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 9, 18, 23, 59),
      );
      expect(result, [
        utc(2026, 9, 4, 7), // Fri (week 0, dtstart itself)
        utc(2026, 9, 7, 7), // Mon (week 1 - across the boundary)
        utc(2026, 9, 11, 7), // Fri (week 1)
        utc(2026, 9, 14, 7), // Mon (week 2)
        utc(2026, 9, 18, 7), // Fri (week 2)
      ]);
    });

    test('WKST changes which weeks are "active" under INTERVAL>1', () {
      // 2026-08-30 is a Sunday and 2026-08-31 (the very next day) is a
      // Monday — the pair straddles the WKST boundary itself, so whether
      // they land in the SAME "week" (and therefore the same active/
      // inactive bucket under INTERVAL=2) depends entirely on WKST:
      // - WKST=MO: Sunday is the LAST day of its week, Monday is the
      //   FIRST day of the NEXT week -> different week indices.
      // - WKST=SU: Sunday is the FIRST day of its week, Monday the
      //   SECOND day of that SAME week -> same week index.
      final dtstart = utc(2026, 8, 30, 8); // Sunday
      final rangeStart = utc(2026, 8, 24);
      final rangeEnd = utc(2026, 9, 20, 23, 59, 59);

      final withMondayStart = expandRruleOccurrences(
        rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;WKST=MO',
        dtstart: dtstart,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
      final withSundayStart = expandRruleOccurrences(
        rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;WKST=SU',
        dtstart: dtstart,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );

      // WKST=MO: 2026-08-31 (Mon) falls in the week right after dtstart's
      // own MO-week — inactive under INTERVAL=2 — so it's excluded.
      expect(withMondayStart, [
        utc(2026, 8, 30, 8),
        utc(2026, 9, 7, 8),
        utc(2026, 9, 13, 8),
      ]);

      // WKST=SU: 2026-08-31 (Mon) is in the SAME SU-week as dtstart
      // itself (both active, week 0) — so it IS included, one day after
      // dtstart, unlike the WKST=MO case above.
      expect(withSundayStart, [
        utc(2026, 8, 30, 8),
        utc(2026, 8, 31, 8),
        utc(2026, 9, 13, 8),
        utc(2026, 9, 14, 8),
      ]);
    });
  });

  group('FREQ=MONTHLY', () {
    test('without INTERVAL recurs on the same day-of-month', () {
      final dtstart = utc(2026, 1, 15, 10);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=MONTHLY',
        dtstart: dtstart,
        rangeStart: utc(2026, 1, 1),
        rangeEnd: utc(2026, 4, 30),
      );
      expect(result, [
        utc(2026, 1, 15, 10),
        utc(2026, 2, 15, 10),
        utc(2026, 3, 15, 10),
        utc(2026, 4, 15, 10),
      ]);
    });

    test('with INTERVAL=3 recurs quarterly', () {
      final dtstart = utc(2026, 1, 15, 10);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=MONTHLY;INTERVAL=3',
        dtstart: dtstart,
        rangeStart: utc(2026, 1, 1),
        rangeEnd: utc(2026, 12, 31),
      );
      expect(result, [
        utc(2026, 1, 15, 10),
        utc(2026, 4, 15, 10),
        utc(2026, 7, 15, 10),
        utc(2026, 10, 15, 10),
      ]);
    });

    test('the 31st-of-the-month rule skips months without a 31st day', () {
      final dtstart = utc(2026, 1, 31, 9); // Jan 31
      final result = expandRruleOccurrences(
        rrule: 'FREQ=MONTHLY',
        dtstart: dtstart,
        rangeStart: utc(2026, 1, 1),
        rangeEnd: utc(2026, 6, 30),
      );
      // Feb (28d), Apr (30d), Jun (30d) have no 31st and are SKIPPED
      // entirely — never clamped to their last day.
      expect(result, [
        utc(2026, 1, 31, 9),
        utc(2026, 3, 31, 9),
        utc(2026, 5, 31, 9),
      ]);
    });
  });

  group('COUNT', () {
    test(
        'terminates the series after exactly COUNT occurrences, regardless of range size',
        () {
      final dtstart = utc(2026, 1, 1, 9);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=DAILY;COUNT=3',
        dtstart: dtstart,
        rangeStart: utc(2020, 1, 1),
        rangeEnd: utc(2030, 1, 1), // a huge range — must not matter
      );
      expect(result, [
        utc(2026, 1, 1, 9),
        utc(2026, 1, 2, 9),
        utc(2026, 1, 3, 9),
      ]);
    });

    test('a range starting after the COUNTed series has ended returns nothing',
        () {
      final dtstart = utc(2026, 1, 1, 9);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=DAILY;COUNT=3',
        dtstart: dtstart,
        rangeStart: utc(2026, 6, 1),
        rangeEnd: utc(2026, 6, 30),
      );
      expect(result, isEmpty);
    });
  });

  group('UNTIL', () {
    test('a date-only UNTIL is inclusive of its whole day', () {
      final dtstart = utc(2026, 1, 1, 9);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=DAILY;UNTIL=20260103',
        dtstart: dtstart,
        rangeStart: utc(2026, 1, 1),
        rangeEnd: utc(2026, 1, 10),
      );
      // Jan 3 (the UNTIL day) is kept; Jan 4 is not.
      expect(result, [
        utc(2026, 1, 1, 9),
        utc(2026, 1, 2, 9),
        utc(2026, 1, 3, 9),
      ]);
    });

    test('a date-time UNTIL is an inclusive exact instant', () {
      final dtstart = utc(2026, 1, 1, 9);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=DAILY;UNTIL=20260103T090000Z',
        dtstart: dtstart,
        rangeStart: utc(2026, 1, 1),
        rangeEnd: utc(2026, 1, 10),
      );
      // The Jan 3 occurrence is at exactly 09:00Z, matching UNTIL exactly
      // -> included. Jan 4 09:00Z is after UNTIL -> excluded.
      expect(result, [
        utc(2026, 1, 1, 9),
        utc(2026, 1, 2, 9),
        utc(2026, 1, 3, 9),
      ]);
    });

    test(
        'an UNTIL one second before an occurrence excludes only that occurrence',
        () {
      final dtstart = utc(2026, 1, 1, 9);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=DAILY;UNTIL=20260103T085959Z',
        dtstart: dtstart,
        rangeStart: utc(2026, 1, 1),
        rangeEnd: utc(2026, 1, 10),
      );
      expect(result, [
        utc(2026, 1, 1, 9),
        utc(2026, 1, 2, 9),
      ]);
    });
  });

  test(
      'a range query over a long-running (unbounded) rule returns only in-range occurrences',
      () {
    // No COUNT, no UNTIL: this rule is unbounded. Querying a narrow window
    // many years after dtstart must still terminate quickly and return
    // only the occurrences actually inside that window.
    final dtstart = utc(2000, 1, 1, 9);
    final result = expandRruleOccurrences(
      rrule: 'FREQ=DAILY',
      dtstart: dtstart,
      rangeStart: utc(2026, 9, 1),
      rangeEnd: utc(2026, 9, 3, 23, 59, 59),
    );
    expect(result, [
      utc(2026, 9, 1, 9),
      utc(2026, 9, 2, 9),
      utc(2026, 9, 3, 9),
    ]);
  });

  group('DST', () {
    test('a recurrence crossing a DST boundary keeps its wall-clock time', () {
      final newYork = tz.getLocation('America/New_York');
      // 2027-03-14 is when America/New_York springs forward (2am -> 3am).
      // A daily 09:00 recurrence starting a few days before must still
      // read 09:00 local a few days after, even though the UTC offset
      // changed by an hour in between.
      final dtstart = tz.TZDateTime(newYork, 2027, 3, 10, 9, 0);
      final result = expandRruleOccurrences(
        rrule: 'FREQ=DAILY',
        dtstart: dtstart,
        rangeStart: tz.TZDateTime(newYork, 2027, 3, 10),
        rangeEnd: tz.TZDateTime(newYork, 2027, 3, 20, 23, 59, 59),
      );

      expect(result, hasLength(11));
      for (final occurrence in result) {
        expect(occurrence.hour, 9,
            reason: 'wall-clock hour must not drift across DST');
        expect(occurrence.minute, 0);
      }

      // Sanity check that a DST transition genuinely happened inside the
      // window (otherwise this test would trivially pass) by confirming
      // the UTC offset differs between the first and last occurrence.
      final firstOffset = (result.first as tz.TZDateTime).timeZone.offset;
      final lastOffset = (result.last as tz.TZDateTime).timeZone.offset;
      expect(firstOffset, isNot(equals(lastOffset)));
    });
  });

  group('expandEventOccurrences', () {
    test('preserves the event\'s own duration on every occurrence', () {
      final event = _event(
        startAt: utc(2026, 9, 1, 9),
        endAt: utc(2026, 9, 1, 10, 30),
        rrule: 'FREQ=DAILY;COUNT=2',
      );
      final result = expandEventOccurrences(
        event,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 9, 5),
      );
      expect(result, hasLength(2));
      expect(result[0].start, utc(2026, 9, 1, 9));
      expect(result[0].end, utc(2026, 9, 1, 10, 30));
      expect(result[1].start, utc(2026, 9, 2, 9));
      expect(result[1].end, utc(2026, 9, 2, 10, 30));
    });

    test('a point-in-time event (no endAt) has a null end on every occurrence',
        () {
      final event =
          _event(startAt: utc(2026, 9, 1, 9), rrule: 'FREQ=DAILY;COUNT=2');
      final result = expandEventOccurrences(
        event,
        rangeStart: utc(2026, 9, 1),
        rangeEnd: utc(2026, 9, 5),
      );
      expect(result.map((o) => o.end), [null, null]);
    });
  });
}
