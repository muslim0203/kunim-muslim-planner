/// Which prayer reminders to schedule, computed purely from settings and the
/// current instant.
///
/// Reminders cover the next [PrayerReminderPlan.days] days. Nothing runs in
/// the background yet (WorkManager lands with Digital Wellbeing), so the
/// window is refreshed whenever the app starts, resumes or a setting changes.
library;

import '../../prayer/domain/daily_prayer_times.dart';
import '../../prayer/domain/prayer_settings.dart';
import 'prayer_reminder_settings.dart';

class PrayerReminder {
  const PrayerReminder({
    required this.id,
    required this.kind,
    required this.at,
    required this.prayerTime,
    required this.leadMinutes,
  });

  /// Stable per day and prayer, so rescheduling replaces rather than
  /// duplicates.
  final int id;
  final PrayerKind kind;

  /// When the reminder fires, as a UTC instant.
  final DateTime at;

  /// The prayer time itself, on the city's wall clock.
  final DateTime prayerTime;
  final int leadMinutes;
}

abstract final class PrayerReminderPlan {
  static const int firstId = 1000;
  static const int days = 7;
  static const int idsPerDay = 10;

  /// Size of the id range owned by prayer reminders.
  static int get idCount => days * idsPerDay;

  static List<PrayerReminder> build({
    required PrayerSettings prayer,
    required PrayerReminderSettings reminders,
    required DateTime now,
  }) {
    final city = prayer.city;
    if (!reminders.enabled || city == null) return const [];

    final today = PrayerDay.wallClock(now, city);
    final nowUtc = now.toUtc();
    final lead = Duration(minutes: reminders.leadMinutes);
    final result = <PrayerReminder>[];
    for (var day = 0; day < days; day++) {
      final slots = PrayerDay.slotsOn(
        prayer,
        city,
        DateTime.utc(today.year, today.month, today.day + day),
      );
      for (final slot in slots) {
        if (!PrayerReminderSettings.selectable.contains(slot.kind) ||
            !reminders.prayers.contains(slot.kind)) {
          continue;
        }
        // Wall-clock time minus the city's offset is the UTC instant.
        final at = slot.time.subtract(city.utcOffset).subtract(lead);
        if (!at.isAfter(nowUtc)) continue;
        result.add(
          PrayerReminder(
            id: firstId + day * idsPerDay + slot.kind.index,
            kind: slot.kind,
            at: at,
            prayerTime: slot.time,
            leadMinutes: reminders.leadMinutes,
          ),
        );
      }
    }
    return result;
  }
}
