import 'package:adhan_dart/adhan_dart.dart' show Madhab;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/prayer/application/prayer_providers.dart';
import 'package:kunim/features/prayer/data/prayer_settings_store.dart';
import 'package:kunim/features/prayer/domain/daily_prayer_times.dart';
import 'package:kunim/features/prayer/domain/prayer_city.dart';
import 'package:kunim/features/prayer/domain/prayer_settings.dart';
import 'package:kunim/features/prayer/presentation/prayer_labels.dart';
import 'package:kunim/features/prayer/presentation/prayer_screen.dart';

/// 14 September 2026, 10:00 in Tashkent.
final _morning = DateTime.utc(2026, 9, 14, 5);

Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _host(AppDatabase db) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      prayerClockProvider.overrideWithValue(() => _morning),
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
      home: const PrayerScreen(),
    ),
  );
}

String _timeOf(WidgetTester tester, PrayerSettings settings, PrayerKind kind) {
  final day = PrayerDay.compute(
    settings: settings,
    city: settings.city!,
    instant: _morning,
  );
  return PrayerLabels.time(
    tester.element(find.byType(PrayerScreen)),
    day.slots[kind.index].time,
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  void useTallView(WidgetTester tester) {
    // Tall enough that every city in the picker sheet is laid out on screen.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('asks for a city, then shows and saves today\'s times', (
    tester,
  ) async {
    useTallView(tester);
    await tester.pumpWidget(_host(db));
    await _pumpFrames(tester);

    final l10n = AppLocalizations.of(tester.element(find.byType(PrayerScreen)));
    expect(find.text(l10n.prayerSetupTitle), findsOneWidget);
    expect(find.text(l10n.prayerNext), findsNothing);

    await tester.tap(find.text(l10n.prayerChooseCity).first);
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.cityTashkent).last);
    await _pumpFrames(tester);

    expect(find.text(l10n.prayerSetupTitle), findsNothing);
    expect(find.text(l10n.prayerNext), findsOneWidget);
    final settings =
        PrayerSettings.defaults.copyWith(city: PrayerCity.tashkent);
    // At 10:00 Dhuhr is next: it shows in the next-prayer card and the list.
    expect(
      find.text(_timeOf(tester, settings, PrayerKind.dhuhr)),
      findsNWidgets(2),
    );
    expect(
        find.text(_timeOf(tester, settings, PrayerKind.fajr)), findsOneWidget);
    expect((await PrayerSettingsStore(db).load()).city, PrayerCity.tashkent);
  });

  testWidgets('changing the madhab recalculates Asr and is saved', (
    tester,
  ) async {
    useTallView(tester);
    final hanafi = PrayerSettings.defaults.copyWith(city: PrayerCity.tashkent);
    await PrayerSettingsStore(db).save(hanafi);

    await tester.pumpWidget(_host(db));
    await _pumpFrames(tester);

    final l10n = AppLocalizations.of(tester.element(find.byType(PrayerScreen)));
    final shafi = hanafi.copyWith(madhab: Madhab.shafi);
    expect(find.text(_timeOf(tester, hanafi, PrayerKind.asr)), findsOneWidget);

    await tester.tap(find.text(l10n.madhabHanafi));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.madhabShafi).last);
    await _pumpFrames(tester);

    expect(find.text(_timeOf(tester, shafi, PrayerKind.asr)), findsOneWidget);
    expect((await PrayerSettingsStore(db).load()).madhab, Madhab.shafi);
  });
}
