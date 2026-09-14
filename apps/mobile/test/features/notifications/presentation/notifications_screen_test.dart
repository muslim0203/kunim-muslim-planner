import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/notifications/local_notifier.dart';
import 'package:kunim/features/notifications/data/prayer_reminder_store.dart';
import 'package:kunim/features/notifications/domain/prayer_reminder_settings.dart';
import 'package:kunim/features/notifications/presentation/notifications_screen.dart';
import 'package:kunim/features/prayer/data/prayer_settings_store.dart';
import 'package:kunim/features/prayer/domain/daily_prayer_times.dart';
import 'package:kunim/features/prayer/domain/prayer_city.dart';
import 'package:kunim/features/prayer/domain/prayer_settings.dart';

import '../../../helpers/fake_local_notifier.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _host(AppDatabase db, FakeLocalNotifier notifier) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      localNotifierProvider.overrideWithValue(notifier),
    ],
    child: MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const NotificationsScreen(),
    ),
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<AppLocalizations> pumpScreen(
    WidgetTester tester,
    FakeLocalNotifier notifier,
  ) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(db, notifier));
    await _pumpFrames(tester);
    return AppLocalizations.of(
      tester.element(find.byType(NotificationsScreen)),
    );
  }

  Future<void> saveCity() => PrayerSettingsStore(db).save(
        PrayerSettings.defaults.copyWith(city: PrayerCity.tashkent),
      );

  testWidgets('asks for a city before reminders can be turned on', (
    tester,
  ) async {
    final l10n = await pumpScreen(tester, FakeLocalNotifier());

    expect(find.text(l10n.notifNeedCityTitle), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('turning reminders on asks for permission and saves', (
    tester,
  ) async {
    await saveCity();
    final notifier = FakeLocalNotifier();
    final l10n = await pumpScreen(tester, notifier);
    expect(find.text(l10n.notifWhichPrayers), findsNothing);

    await tester.tap(find.text(l10n.notifPrayerTitle));
    await _pumpFrames(tester);

    expect(notifier.permissionRequests, 1);
    expect((await PrayerReminderStore(db).load()).enabled, isTrue);
    expect(find.text(l10n.notifWhichPrayers), findsOneWidget);

    await tester.tap(find.text(l10n.prayerFajr));
    await _pumpFrames(tester);

    final saved = await PrayerReminderStore(db).load();
    expect(saved.prayers, isNot(contains(PrayerKind.fajr)));
    expect(saved.prayers, contains(PrayerKind.isha));
  });

  testWidgets('a denied permission leaves reminders off and says why', (
    tester,
  ) async {
    await saveCity();
    final l10n = await pumpScreen(tester, FakeLocalNotifier(grants: false));

    await tester.tap(find.text(l10n.notifPrayerTitle));
    await _pumpFrames(tester);

    expect(find.text(l10n.notifPermissionDenied), findsOneWidget);
    expect((await PrayerReminderStore(db).load()).enabled, isFalse);
    expect(find.text(l10n.notifWhichPrayers), findsNothing);
  });

  testWidgets('without exact alarms it warns and opens the system setting', (
    tester,
  ) async {
    await saveCity();
    await PrayerReminderStore(db).save(
      PrayerReminderSettings.defaults.copyWith(enabled: true),
    );
    final notifier = FakeLocalNotifier(
      enabled: true,
      managesExactAlarms: true,
      exactAllowed: false,
    );
    final l10n = await pumpScreen(tester, notifier);

    expect(find.text(l10n.notifExactTitle), findsOneWidget);
    await tester.tap(find.text(l10n.notifExactAction));
    await _pumpFrames(tester);

    expect(notifier.exactSettingsOpened, 1);
  });
}
