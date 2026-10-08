// The statistics screen's points card and day-by-day grid, against real
// rows: a day everything was done on, and a day something was missed.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/app/theme/tokens.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/habits/data/habit_log_repository.dart';
import 'package:kunim/features/habits/data/habit_repository.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/stats/presentation/daily_analysis.dart';
import 'package:kunim/features/stats/presentation/stats_screen.dart';

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
    tester.view.physicalSize = const Size(800, 4000);
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

  /// Today's square is the last one in the grid.
  Finder todaySquare() => find
      .descendant(
        of: find.byType(DailyAnalysisCard),
        matching: find.byType(InkWell),
      )
      .last;

  /// Scoped to the day sheet: the grid's legend uses the same words.
  Finder inSheet(String text) => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(text),
      );

  testWidgets('a day with everything done earns its points', (tester) async {
    final habitId = await HabitRepository(db, onLocalWrite: () {}).createHabit(
      title: 'Kitob o‘qish',
    );
    await HabitLogRepository(db, onLocalWrite: () {})
        .logCompletion(habitId: habitId, day: LocalDay.now());

    final l10n = await pumpStats(tester);

    // One widget done (10) + everything done (20) + first day of the run (5).
    expect(find.text(l10n.statsPointsToday(35)), findsOneWidget);
    expect(find.text(l10n.statsLevel(1)), findsOneWidget);
    expect(find.text(l10n.statsDailyTitle), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a missed widget shows in the day it was missed on', (
    tester,
  ) async {
    await HabitRepository(db, onLocalWrite: () {}).createHabit(title: 'Sport');

    final l10n = await pumpStats(tester);
    expect(find.text(l10n.statsPointsToday(0)), findsOneWidget);

    await tester.tap(todaySquare());
    await _pumpFrames(tester);

    expect(inSheet(l10n.statsDayMissedTitle), findsOneWidget);
    expect(inSheet(l10n.statsDaySummary(0, 1)), findsOneWidget);
    expect(inSheet('Sport'), findsOneWidget);
    expect(inSheet(l10n.statsDayDoneTitle), findsNothing);
    await unmount(tester);
  });

  testWidgets('a day with nothing planned is free, not failed', (tester) async {
    final l10n = await pumpStats(tester);

    await tester.tap(todaySquare());
    await _pumpFrames(tester);

    expect(inSheet(l10n.statsDayFree), findsOneWidget);
    expect(inSheet(l10n.statsDayMissedTitle), findsNothing);
    await unmount(tester);
  });

  /// The colour painted inside a day square.
  Color squareColour(WidgetTester tester, Finder square) {
    final container = tester.widget<Container>(
      find.descendant(of: square, matching: find.byType(Container)).first,
    );
    return (container.decoration! as BoxDecoration).color!;
  }

  testWidgets('a day still being lived is never painted as missed', (
    tester,
  ) async {
    // A widget due today and nothing logged yet: `done == 0`, which used to
    // colour the square with the error colour. The day has hours left in it,
    // and these indicators exist to help someone decide, not to call a
    // failure early (CLAUDE.md, TZ section 78).
    await HabitRepository(db, onLocalWrite: () {}).createHabit(title: 'Sport');

    await pumpStats(tester);
    final theme = Theme.of(tester.element(find.byType(DailyAnalysisCard)));

    final colour = squareColour(tester, todaySquare());
    expect(
      colour,
      isNot(theme.colorScheme.error),
      reason: 'today has not been missed; the day is not over',
    );
    expect(colour, KunimColors.gold, reason: 'a day in progress reads amber');
    await unmount(tester);
  });

  testWidgets('finishing the day turns today green', (tester) async {
    final habitId = await HabitRepository(db, onLocalWrite: () {}).createHabit(
      title: 'Sport',
    );
    await HabitLogRepository(db, onLocalWrite: () {})
        .logCompletion(habitId: habitId, day: LocalDay.now());

    await pumpStats(tester);
    final theme = Theme.of(tester.element(find.byType(DailyAnalysisCard)));

    expect(squareColour(tester, todaySquare()), theme.colorScheme.primary);
    await unmount(tester);
  });
}
