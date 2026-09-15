// The statistics screen shows this week's daily log numbers from real
// entries, and says so plainly when there are none.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/family/data/family_log_repository.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/health/data/health_log_repository.dart';
import 'package:kunim/features/mood/data/mood_log_repository.dart';
import 'package:kunim/features/prayer/data/prayer_log_repository.dart';
import 'package:kunim/features/prayer/domain/prayer_log_status.dart';
import 'package:kunim/features/sleep/data/sleep_log_repository.dart';
import 'package:kunim/features/stats/presentation/stats_screen.dart';
import 'package:kunim/shared/widgets/kunim_widgets.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<AppLocalizations> pumpStats(WidgetTester tester) async {
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
          home: const StatsScreen(),
        ),
      ),
    );
    await _pumpFrames(tester);
    return AppLocalizations.of(tester.element(find.byType(StatsScreen)));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 3);
  }

  testWidgets('without entries every daily log area says so', (tester) async {
    final l10n = await pumpStats(tester);

    // Mood, sleep, health, family and prayers.
    expect(find.text(l10n.statsNoEntriesWeek), findsNWidgets(5));
    // Only the Qur'an row is still coming soon.
    expect(find.byType(ComingSoonBadge), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('this week\'s entries appear in their areas', (tester) async {
    final today = LocalDay.now();
    final wake = DateTime.now();
    await MoodLogRepository(db, onLocalWrite: () {})
        .saveForDay(today, score: 4);
    await SleepLogRepository(db, onLocalWrite: () {}).saveForDay(
      today,
      bedTime: wake.subtract(const Duration(hours: 8)),
      wakeTime: wake,
      quality: 5,
    );
    await HealthLogRepository(db, onLocalWrite: () {})
        .saveForDay(today, workoutMin: 45);
    await FamilyLogRepository(db, onLocalWrite: () {})
        .saveForDay(today, minutes: 60);
    await PrayerLogRepository(db, onLocalWrite: () {})
        .mark(today, 'fajr', PrayerLogStatus.alone);

    final l10n = await pumpStats(tester);

    expect(find.text(l10n.statsNoEntriesWeek), findsNothing);
    expect(
      find.textContaining(l10n.statsSleepAverage(l10n.durationHoursOnly(8))),
      findsOneWidget,
    );
    expect(
      find.textContaining(l10n.statsWorkoutTotal(l10n.durationMinutesOnly(45))),
      findsOneWidget,
    );
    expect(
      find.textContaining(l10n.statsFamilyTotal(l10n.durationHoursOnly(1))),
      findsOneWidget,
    );
    expect(find.textContaining(l10n.statsPrayersMarked(1)), findsOneWidget);
    expect(find.textContaining('/5'), findsNWidgets(2));
    await unmount(tester);
  });
}
