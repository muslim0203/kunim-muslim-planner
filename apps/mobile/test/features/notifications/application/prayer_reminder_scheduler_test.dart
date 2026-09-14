import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/notifications/local_notifier.dart';
import 'package:kunim/core/settings/app_settings.dart';
import 'package:kunim/features/notifications/application/notification_providers.dart';
import 'package:kunim/features/notifications/data/prayer_reminder_store.dart';
import 'package:kunim/features/notifications/domain/prayer_reminder_plan.dart';
import 'package:kunim/features/notifications/domain/prayer_reminder_settings.dart';
import 'package:kunim/features/prayer/application/prayer_providers.dart';
import 'package:kunim/features/prayer/data/prayer_settings_store.dart';
import 'package:kunim/features/prayer/domain/daily_prayer_times.dart';
import 'package:kunim/features/prayer/domain/prayer_city.dart';
import 'package:kunim/features/prayer/domain/prayer_settings.dart';

import '../../../helpers/fake_local_notifier.dart';

/// 14 September 2026, 10:00 in Tashkent.
final _morning = DateTime.utc(2026, 9, 14, 5);
final _tashkent = PrayerSettings.defaults.copyWith(city: PrayerCity.tashkent);

void main() {
  // The scheduler listens for app resume through the widgets binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeLocalNotifier notifier;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    notifier = FakeLocalNotifier(enabled: true);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        localNotifierProvider.overrideWithValue(notifier),
        prayerClockProvider.overrideWithValue(() => _morning),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> saveEnabled({int leadMinutes = 0}) async {
    await PrayerSettingsStore(db).save(_tashkent);
    await PrayerReminderStore(db).save(
      PrayerReminderSettings.defaults.copyWith(
        enabled: true,
        leadMinutes: leadMinutes,
      ),
    );
  }

  test('schedules the week of reminders in the app language', () async {
    await saveEnabled(leadMinutes: 10);

    await container.read(prayerReminderSchedulerProvider).reschedule();

    final l10n = lookupAppLocalizations(AppSettings.defaults.language.locale);
    expect(
      notifier.replacedRange,
      (PrayerReminderPlan.firstId, PrayerReminderPlan.idCount),
    );
    expect(notifier.channel?.name, l10n.reminderChannelPrayer);
    expect(notifier.scheduled, hasLength(4 + 6 * 5));

    final first = notifier.scheduled.first;
    final dhuhr = PrayerDay.compute(
      settings: _tashkent,
      city: PrayerCity.tashkent,
      instant: _morning,
    ).slots[PrayerKind.dhuhr.index].time;
    expect(first.id, PrayerReminderPlan.firstId + PrayerKind.dhuhr.index);
    expect(first.at, dhuhr.subtract(const Duration(hours: 5, minutes: 10)));
    expect(first.title, l10n.reminderPrayerSoonTitle(l10n.prayerDhuhr, 10));
    expect(
      first.body,
      l10n.reminderPrayerSoonBody(
        l10n.prayerDhuhr,
        '${dhuhr.hour}:${dhuhr.minute.toString().padLeft(2, '0')}',
      ),
    );
  });

  test('turning reminders off clears every scheduled one', () async {
    await saveEnabled();
    final scheduler = container.read(prayerReminderSchedulerProvider);
    await scheduler.reschedule();
    expect(notifier.scheduled, isNotEmpty);

    await container
        .read(prayerReminderSettingsProvider.notifier)
        .edit((settings) => settings.copyWith(enabled: false));
    await scheduler.reschedule();

    expect(notifier.scheduled, isEmpty);
    expect(
      notifier.replacedRange,
      (PrayerReminderPlan.firstId, PrayerReminderPlan.idCount),
    );
  });

  test('changing the app language rewrites the texts', () async {
    await saveEnabled();
    final scheduler = container.read(prayerReminderSchedulerProvider);
    await scheduler.reschedule();

    await container
        .read(appSettingsProvider.notifier)
        .setLanguage(AppLanguage.ru);
    await scheduler.reschedule();

    final ru = lookupAppLocalizations(AppLanguage.ru.locale);
    expect(
      notifier.scheduled.first.title,
      ru.reminderPrayerNowTitle(ru.prayerDhuhr),
    );
  });
}
