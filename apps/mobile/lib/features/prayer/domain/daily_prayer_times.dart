/// One day of prayer times for a city, computed offline with `adhan_dart`.
///
/// All times are the city's wall-clock time, carried in UTC-flagged
/// [DateTime]s so the device's own time zone is never applied to them: a
/// phone set to another zone still shows the times of the chosen city.
library;

import 'package:adhan_dart/adhan_dart.dart' as adhan;

import 'prayer_city.dart';
import 'prayer_settings.dart';

/// The six daily times in order. Sunrise is not a prayer but marks the end
/// of Fajr, so it is listed (and can be "next") like the others.
enum PrayerKind { fajr, sunrise, dhuhr, asr, maghrib, isha }

class PrayerSlot {
  const PrayerSlot(this.kind, this.time);

  final PrayerKind kind;

  /// Wall-clock time in the city (see the library comment).
  final DateTime time;
}

class PrayerDay {
  const PrayerDay._({
    required this.slots,
    required this.nextIndex,
    required this.next,
    required this.now,
  });

  /// Today's six times, one per [PrayerKind], in order.
  final List<PrayerSlot> slots;

  /// Index into [slots] of the next time today, or `null` after Isha, when
  /// [next] is tomorrow's Fajr.
  final int? nextIndex;
  final PrayerSlot next;

  /// The city's wall clock at the moment this was computed.
  final DateTime now;

  Duration get untilNext => next.time.difference(now);

  static PrayerDay compute({
    required PrayerSettings settings,
    required PrayerCity city,
    required DateTime instant,
  }) {
    final now = wallClock(instant, city);
    final today =
        slotsOn(settings, city, DateTime.utc(now.year, now.month, now.day));
    for (var i = 0; i < today.length; i++) {
      if (today[i].time.isAfter(now)) {
        return PrayerDay._(
          slots: today,
          nextIndex: i,
          next: today[i],
          now: now,
        );
      }
    }
    final tomorrow = slotsOn(
      settings,
      city,
      DateTime.utc(now.year, now.month, now.day + 1),
    );
    return PrayerDay._(
      slots: today,
      nextIndex: null,
      next: tomorrow.first,
      now: now,
    );
  }

  /// [instant] expressed as the city's wall-clock time.
  static DateTime wallClock(DateTime instant, PrayerCity city) =>
      instant.toUtc().add(city.utcOffset);

  /// The six times of the city's calendar [day] (a UTC date).
  static List<PrayerSlot> slotsOn(
    PrayerSettings settings,
    PrayerCity city,
    DateTime day,
  ) {
    final parameters = settings.method.parameters()..madhab = settings.madhab;
    final times = adhan.PrayerTimes(
      // UTC so the calendar date is never shifted by the device's zone.
      date: DateTime.utc(day.year, day.month, day.day),
      coordinates: city.coordinates,
      calculationParameters: parameters,
    );
    DateTime wall(DateTime moment) => wallClock(moment, city);
    return [
      PrayerSlot(PrayerKind.fajr, wall(times.fajr)),
      PrayerSlot(PrayerKind.sunrise, wall(times.sunrise)),
      PrayerSlot(PrayerKind.dhuhr, wall(times.dhuhr)),
      PrayerSlot(PrayerKind.asr, wall(times.asr)),
      PrayerSlot(PrayerKind.maghrib, wall(times.maghrib)),
      PrayerSlot(PrayerKind.isha, wall(times.isha)),
    ];
  }
}
