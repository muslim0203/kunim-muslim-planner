// The analysis as the user meets it: which area is slipping, and the one
// thing to do about it.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/habits/domain/habit_kind.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/insights/presentation/insights_view.dart';
import 'package:kunim/features/onboarding/data/onboarding_answers_store.dart';
import 'package:kunim/features/onboarding/domain/onboarding_answers.dart';
import 'package:kunim/features/stats/application/weekly_stats_provider.dart';

final _today = LocalDay(2026, 10, 22);

Future<void> _pumpFrames(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// A widget that has existed for the whole window, scheduled every day.
  Future<void> seedHabit({
    required String id,
    required String title,
    required HabitKind kind,
    int target = 1,
    int? reminderMinutes,
  }) {
    final created = DateTime(2026, 10, 1).toUtc();
    return db.into(db.habits).insert(
          HabitsCompanion.insert(
            id: Value(id),
            createdAt: Value(created),
            updatedAt: Value(created),
            title: title,
            frequency: const Value('{"type":"every_day"}'),
            targetCount: Value(target),
            kind: Value(kind.code),
            reminderMinutes: Value(reminderMinutes),
          ),
        );
  }

  /// Marks [days] of the window as done, counting back from today.
  Future<void> seedLogs(String habitId,
      {required int days, int count = 1}) async {
    for (var offset = 0; offset < days; offset++) {
      final day = _today.addDays(-offset);
      await db.into(db.habitLogs).insert(
            HabitLogsCompanion.insert(
              id: Value('$habitId-$offset'),
              habitId: habitId,
              date: day.toUtcMidnight(),
              count: Value(count),
            ),
          );
    }
  }

  Future<AppLocalizations> pumpInsights(
    WidgetTester tester, {
    List<String> focusAreas = const [],
  }) async {
    // What the device remembers being answered at sign-up — the analysis
    // reads this, never the account.
    await OnboardingAnswersStore(db).save(
      OnboardingAnswers.fromSlugs(focusAreas: focusAreas),
    );
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          statsTodayProvider.overrideWithValue(_today),
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
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: InsightsView(),
            ),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
    return AppLocalizations.of(tester.element(find.byType(InsightsView)));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 3);
  }

  testWidgets('with nothing recorded it says so instead of guessing', (
    tester,
  ) async {
    final l10n = await pumpInsights(tester);

    expect(find.text(l10n.insightsEmpty), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the slipping area comes first and says what to do', (
    tester,
  ) async {
    await seedHabit(
      id: 'h-sport',
      title: 'Sport',
      kind: HabitKind.sport,
      target: 30,
      reminderMinutes: 7 * 60 + 30,
    );
    await seedHabit(id: 'h-book', title: 'Kitob', kind: HabitKind.book);
    await seedLogs('h-book', days: 14);

    final l10n = await pumpInsights(tester);

    // Health is named as the area needing attention; reading is not.
    expect(
      find.text(l10n.insightsWeakest(l10n.moduleHealth)),
      findsOneWidget,
    );
    expect(find.text(l10n.insightsStateSlipping), findsOneWidget);
    expect(find.text(l10n.insightsStateStrong), findsOneWidget);
    // Thirty minutes was never once done, so the amount is what gives.
    expect(find.text(l10n.insightsAdviceLowerTarget), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, l10n.insightsOpenWidget),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('a day nobody planned is never held against the user', (
    tester,
  ) async {
    // Scheduled on Mondays only, done on both Mondays in the window.
    final created = DateTime(2026, 10, 1).toUtc();
    await db.into(db.habits).insert(
          HabitsCompanion.insert(
            id: const Value('h-weekly'),
            createdAt: Value(created),
            updatedAt: Value(created),
            title: 'Oila',
            frequency:
                const Value('{"type":"specific_weekdays","weekdays":[1]}'),
            targetCount: const Value(30),
            kind: Value(HabitKind.family.code),
          ),
        );
    for (final day in [LocalDay(2026, 10, 12), LocalDay(2026, 10, 19)]) {
      await db.into(db.habitLogs).insert(
            HabitLogsCompanion.insert(
              id: Value('fam-${day.day}'),
              habitId: 'h-weekly',
              date: day.toUtcMidnight(),
              count: const Value(30),
            ),
          );
    }

    final l10n = await pumpInsights(tester);

    // Two planned days, both done — not 2 out of 14.
    expect(find.text(l10n.insightsDaysDone(2, 2)), findsOneWidget);
    expect(find.text(l10n.insightsStateStrong), findsWidgets);
    await unmount(tester);
  });

  testWidgets('an area the user asked for but never started is named', (
    tester,
  ) async {
    await seedHabit(id: 'h-book', title: 'Kitob', kind: HabitKind.book);
    await seedLogs('h-book', days: 14);

    final l10n = await pumpInsights(tester, focusAreas: const ['quran']);

    expect(find.text(l10n.moduleQuran), findsOneWidget);
    expect(find.text(l10n.insightsStateUntouched), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, l10n.homeWidgetAdd),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('opening the widget from the advice leads to its settings', (
    tester,
  ) async {
    await seedHabit(
      id: 'h-sport',
      title: 'Sport',
      kind: HabitKind.sport,
      target: 30,
    );

    final l10n = await pumpInsights(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.insightsOpenWidget),
    );
    await _pumpFrames(tester, 20);

    expect(find.text(l10n.habitEdit), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Sport'), findsOneWidget);
    await unmount(tester);
  });
}
