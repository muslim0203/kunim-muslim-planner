// The four daily log screens: add today's entry through the editor sheet,
// and delete it only after confirming.
//
// Rows are read back with plain one-shot queries, never `watch().first`: a
// Drift stream inside `testWidgets`' fake-async zone waits on timers that
// only advance when the test pumps, so awaiting one directly hangs the test.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/family/data/family_log_repository.dart';
import 'package:kunim/features/family/presentation/family_screen.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/health/presentation/health_screen.dart';
import 'package:kunim/features/mood/data/mood_log_repository.dart';
import 'package:kunim/features/mood/presentation/mood_screen.dart';
import 'package:kunim/features/sleep/presentation/sleep_screen.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  DateTime today() => LocalDay.now().toUtcMidnight();

  Future<MoodLog?> liveMood() => (db.select(db.moodLogs)
        ..where((l) => l.date.equals(today()) & l.deletedAt.isNull()))
      .getSingleOrNull();

  Future<AppLocalizations> pumpScreen(
      WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncTriggerSchedulerProvider.overrideWithValue(
            SyncTriggerScheduler(runSync: ({bool force = false}) async {}),
          ),
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
          home: screen,
        ),
      ),
    );
    await _pumpFrames(tester);
    return AppLocalizations.of(tester.element(find.byType(Scaffold).first));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 3);
  }

  testWidgets('mood: add today with a score and a feeling', (tester) async {
    final l10n = await pumpScreen(tester, const MoodScreen());
    expect(find.text(l10n.logTodayEmpty), findsOneWidget);

    await tester.tap(find.text(l10n.logAdd));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.moodScore4));
    await tester.tap(find.text(l10n.moodTagGrateful));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.logSave));
    await _pumpFrames(tester);

    final saved = await liveMood();
    expect(saved?.score, 4);
    expect(MoodLogRepository.tagsOf(saved!), ['grateful']);
    expect(find.text(l10n.logTodayEmpty), findsNothing);
    expect(
      find.text('${l10n.moodScore4}, ${l10n.moodTagGrateful}'),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('mood: deleting asks first', (tester) async {
    await MoodLogRepository(db, onLocalWrite: () {})
        .saveForDay(LocalDay.now(), score: 2);
    final l10n = await pumpScreen(tester, const MoodScreen());

    await tester.tap(find.text(l10n.logEdit));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.logDelete));
    await _pumpFrames(tester);
    expect(find.text(l10n.logDeleteConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.logDelete).last);
    await _pumpFrames(tester);

    expect(await liveMood(), isNull);
    expect(find.text(l10n.logTodayEmpty), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('sleep: the default night is saved with its duration',
      (tester) async {
    final l10n = await pumpScreen(tester, const SleepScreen());

    await tester.tap(find.text(l10n.logAdd));
    await _pumpFrames(tester);
    // 23:00 -> 07:00 by default.
    expect(
      find.text('${l10n.sleepDuration}: ${l10n.durationHoursOnly(8)}'),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.sleepQuality4));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.logSave));
    await _pumpFrames(tester);

    final saved = await (db.select(db.sleepLogs)
          ..where((l) => l.date.equals(today()) & l.deletedAt.isNull()))
        .getSingleOrNull();
    expect(saved?.durationMin, 480);
    expect(saved?.quality, 4);
    await unmount(tester);
  });

  testWidgets('health: needs a value, then saves it; says it is not advice',
      (tester) async {
    final l10n = await pumpScreen(tester, const HealthScreen());
    expect(find.text(l10n.healthDisclaimer), findsOneWidget);

    await tester.tap(find.text(l10n.logAdd));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.logSave));
    await _pumpFrames(tester);
    expect(find.text(l10n.healthNeedValue), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, l10n.healthWater),
      '750',
    );
    await tester.tap(find.text(l10n.logSave));
    await _pumpFrames(tester);

    final saved = await (db.select(db.healthLogs)
          ..where((l) => l.date.equals(today()) & l.deletedAt.isNull()))
        .getSingleOrNull();
    expect(saved?.waterMl, 750);
    expect(saved?.steps, isNull);
    await unmount(tester);
  });

  testWidgets('family: quick time and an activity', (tester) async {
    final l10n = await pumpScreen(tester, const FamilyScreen());

    await tester.tap(find.text(l10n.logAdd));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.durationHoursOnly(1)));
    await tester.tap(find.text(l10n.familyActivityWalk));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.logSave));
    await _pumpFrames(tester);

    final saved = await (db.select(db.familyLogs)
          ..where((l) => l.date.equals(today()) & l.deletedAt.isNull()))
        .getSingleOrNull();
    expect(saved?.minutes, 60);
    expect(FamilyLogRepository.activitiesOf(saved!), ['walk']);
    await unmount(tester);
  });
}
