import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/notifications/domain/prayer_reminder_plan.dart';
import 'package:kunim/features/notifications/domain/prayer_reminder_settings.dart';
import 'package:kunim/features/prayer/domain/daily_prayer_times.dart';
import 'package:kunim/features/prayer/domain/prayer_city.dart';
import 'package:kunim/features/prayer/domain/prayer_settings.dart';

final _prayer = PrayerSettings.defaults.copyWith(city: PrayerCity.tashkent);
final _on = PrayerReminderSettings.defaults.copyWith(enabled: true);

/// 14 September 2026, 10:00 in Tashkent.
final _morning = DateTime.utc(2026, 9, 14, 5);

DateTime _prayerTime(PrayerKind kind, DateTime instant) => PrayerDay.compute(
      settings: _prayer,
      city: PrayerCity.tashkent,
      instant: instant,
    ).slots[kind.index].time;

void main() {
  test('nothing is scheduled while reminders are off or no city is set', () {
    expect(
      PrayerReminderPlan.build(
        prayer: _prayer,
        reminders: PrayerReminderSettings.defaults,
        now: _morning,
      ),
      isEmpty,
    );
    expect(
      PrayerReminderPlan.build(
        prayer: PrayerSettings.defaults,
        reminders: _on,
        now: _morning,
      ),
      isEmpty,
    );
  });

  test('a week of the five prayers, skipping what has already passed', () {
    final plan = PrayerReminderPlan.build(
        prayer: _prayer, reminders: _on, now: _morning);

    // Today Fajr (and sunrise) are over at 10:00: 4 left today + 6 full days.
    expect(plan, hasLength(4 + 6 * 5));
    expect(plan.map((r) => r.kind), isNot(contains(PrayerKind.sunrise)));
    expect(plan.first.kind, PrayerKind.dhuhr);
    expect(
      plan.every((r) => r.at.isUtc && r.at.isAfter(_morning)),
      isTrue,
    );

    final ids = plan.map((r) => r.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(
        id,
        inInclusiveRange(
          PrayerReminderPlan.firstId,
          PrayerReminderPlan.firstId + PrayerReminderPlan.idCount - 1,
        ),
      );
    }
  });

  test('fires at the prayer time converted to a UTC instant', () {
    final first =
        PrayerReminderPlan.build(prayer: _prayer, reminders: _on, now: _morning)
            .first;
    final dhuhr = _prayerTime(PrayerKind.dhuhr, _morning);

    expect(first.id, PrayerReminderPlan.firstId + PrayerKind.dhuhr.index);
    expect(first.prayerTime, dhuhr);
    // Tashkent is UTC+5.
    expect(first.at, dhuhr.subtract(const Duration(hours: 5)));
  });

  test('a lead time moves the reminder earlier and can skip a close prayer',
      () {
    final dhuhr = _prayerTime(PrayerKind.dhuhr, _morning);
    // Five minutes before Dhuhr, a 15-minute reminder for it is too late.
    final now = dhuhr.subtract(const Duration(hours: 5, minutes: 5));
    final plan = PrayerReminderPlan.build(
      prayer: _prayer,
      reminders: _on.copyWith(leadMinutes: 15),
      now: now,
    );

    expect(plan.first.kind, PrayerKind.asr);
    final asr = _prayerTime(PrayerKind.asr, now);
    expect(
      plan.first.at,
      asr.subtract(const Duration(hours: 5, minutes: 15)),
    );
  });

  test('only the chosen prayers, and never sunrise', () {
    final plan = PrayerReminderPlan.build(
      prayer: _prayer,
      reminders: _on.copyWith(
        prayers: {PrayerKind.fajr, PrayerKind.sunrise},
      ),
      now: _morning,
    );

    // Today's Fajr has passed; the next six days remain.
    expect(plan, hasLength(6));
    expect(plan.every((r) => r.kind == PrayerKind.fajr), isTrue);
  });
}
