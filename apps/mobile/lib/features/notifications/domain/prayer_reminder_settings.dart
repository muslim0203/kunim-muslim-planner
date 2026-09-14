import 'package:flutter/foundation.dart';

import '../../prayer/domain/daily_prayer_times.dart';

@immutable
class PrayerReminderSettings {
  const PrayerReminderSettings({
    required this.enabled,
    required this.prayers,
    required this.leadMinutes,
  });

  /// The five daily prayers. Sunrise is listed in the timetable but is not
  /// a prayer, so it is never offered as a reminder.
  static const List<PrayerKind> selectable = [
    PrayerKind.fajr,
    PrayerKind.dhuhr,
    PrayerKind.asr,
    PrayerKind.maghrib,
    PrayerKind.isha,
  ];

  /// How early a reminder may come, in minutes; 0 is at the time itself.
  static const List<int> leadChoices = [0, 5, 10, 15, 30];

  /// Off until the user turns reminders on and allows notifications.
  static const PrayerReminderSettings defaults = PrayerReminderSettings(
    enabled: false,
    prayers: {
      PrayerKind.fajr,
      PrayerKind.dhuhr,
      PrayerKind.asr,
      PrayerKind.maghrib,
      PrayerKind.isha,
    },
    leadMinutes: 0,
  );

  final bool enabled;
  final Set<PrayerKind> prayers;
  final int leadMinutes;

  PrayerReminderSettings copyWith({
    bool? enabled,
    Set<PrayerKind>? prayers,
    int? leadMinutes,
  }) {
    return PrayerReminderSettings(
      enabled: enabled ?? this.enabled,
      prayers: prayers ?? this.prayers,
      leadMinutes: leadMinutes ?? this.leadMinutes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrayerReminderSettings &&
      other.enabled == enabled &&
      setEquals(other.prayers, prayers) &&
      other.leadMinutes == leadMinutes;

  @override
  int get hashCode =>
      Object.hash(enabled, Object.hashAllUnordered(prayers), leadMinutes);
}
