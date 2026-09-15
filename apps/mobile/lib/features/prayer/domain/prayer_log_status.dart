/// How a prayer was marked, and which prayers can be marked.
library;

import 'daily_prayer_times.dart';

/// ADR-0002 rule 10. [code] is the wire value; the declaration order is the
/// server's merge order (`none < qaza < alone < jamaah`, max-wins).
enum PrayerLogStatus {
  none('none'),
  qaza('qaza'),
  alone('alone'),
  jamaah('jamaah');

  const PrayerLogStatus(this.code);

  final String code;

  /// `null` for a code this build does not know.
  static PrayerLogStatus? fromCode(String? code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return null;
  }
}

/// The wire key of a prayer that can be marked, or `null` for sunrise, which
/// is a time and not a prayer.
String? prayerLogKey(PrayerKind kind) {
  return switch (kind) {
    PrayerKind.fajr => 'fajr',
    PrayerKind.dhuhr => 'dhuhr',
    PrayerKind.asr => 'asr',
    PrayerKind.maghrib => 'maghrib',
    PrayerKind.isha => 'isha',
    PrayerKind.sunrise => null,
  };
}

/// Every key [prayerLogKey] can return.
const Set<String> prayerLogKeys = {'fajr', 'dhuhr', 'asr', 'maghrib', 'isha'};
