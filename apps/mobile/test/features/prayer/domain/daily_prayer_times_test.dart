import 'package:adhan_dart/adhan_dart.dart' show Madhab;
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/prayer/domain/daily_prayer_times.dart';
import 'package:kunim/features/prayer/domain/prayer_city.dart';
import 'package:kunim/features/prayer/domain/prayer_settings.dart';

const _settings = PrayerSettings(
  city: PrayerCity.tashkent,
  method: PrayerMethod.muslimWorldLeague,
  madhab: Madhab.hanafi,
);

PrayerDay _at(DateTime instant, [PrayerSettings settings = _settings]) =>
    PrayerDay.compute(
      settings: settings,
      city: PrayerCity.tashkent,
      instant: instant,
    );

/// 14 September 2026, 10:00 in Tashkent (05:00 UTC).
final _morning = DateTime.utc(2026, 9, 14, 5);

void main() {
  test('six times for the city\'s own calendar day, in order', () {
    final day = _at(_morning);

    expect(day.slots.map((slot) => slot.kind), PrayerKind.values);
    for (var i = 1; i < day.slots.length; i++) {
      expect(day.slots[i].time.isAfter(day.slots[i - 1].time), isTrue);
    }
    for (final slot in day.slots) {
      expect(
        (slot.time.year, slot.time.month, slot.time.day),
        (2026, 9, 14),
        reason: '${slot.kind} is on the wrong day',
      );
    }
  });

  test('times are Tashkent wall-clock time, not UTC or the device zone', () {
    // Solar noon in Tashkent in mid-September falls shortly after 12:15.
    final dhuhr = _at(_morning).slots[PrayerKind.dhuhr.index].time;
    expect(dhuhr.hour, 12);
    expect(dhuhr.minute, inInclusiveRange(5, 40));
  });

  test('the same instant gives the same times whatever the device zone', () {
    final utc = _at(_morning);
    final local = _at(_morning.toLocal());
    expect(
      local.slots.map((slot) => slot.time),
      utc.slots.map((slot) => slot.time),
    );
  });

  test('Hanafi Asr is later than the standard Asr', () {
    final hanafi = _at(_morning).slots[PrayerKind.asr.index].time;
    final standard = _at(
      _morning,
      _settings.copyWith(madhab: Madhab.shafi),
    ).slots[PrayerKind.asr.index].time;

    expect(hanafi.isAfter(standard), isTrue);
  });

  test('the next time is the first one still ahead', () {
    final day = _at(_morning);

    expect(day.nextIndex, PrayerKind.dhuhr.index);
    expect(day.next.kind, PrayerKind.dhuhr);
    expect(day.untilNext.isNegative, isFalse);
    expect(day.untilNext, day.next.time.difference(day.now));
  });

  test('after Isha the next time is tomorrow\'s Fajr', () {
    // 23:50 in Tashkent.
    final day = _at(DateTime.utc(2026, 9, 14, 18, 50));

    expect(day.nextIndex, isNull);
    expect(day.next.kind, PrayerKind.fajr);
    expect(day.next.time.day, 15);
    expect(day.slots.first.time.day, 14);
  });
}
