// The home screen's headline progress card.
//
// It used to count TASKS alone. With a widget due and no task it therefore
// announced "nothing planned for today" directly above a grid reading
// "0/1 done" — two counters on one screen disagreeing about the same day.
// The card speaks for the whole day, so it counts everything the day asked
// for.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/habits/data/habit_log_repository.dart';
import 'package:kunim/features/habits/data/habit_repository.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/home/presentation/home_screen.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<AppLocalizations> pumpHome(WidgetTester tester) async {
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
          home: const HomeScreen(),
        ),
      ),
    );
    await _pumpFrames(tester);
    return AppLocalizations.of(tester.element(find.byType(HomeScreen)));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 3);
  }

  testWidgets('a widget due today counts as planned, with no task at all', (
    tester,
  ) async {
    await HabitRepository(db, onLocalWrite: () {}).createHabit(title: 'Sport');

    final l10n = await pumpHome(tester);

    expect(
      find.text(l10n.homeNothingPlanned),
      findsNothing,
      reason: 'a widget is due, so the day is not empty',
    );
    expect(find.text(l10n.homeProgressSummary(0, 1)), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('doing the widget moves the card, not just the grid', (
    tester,
  ) async {
    final habitId = await HabitRepository(db, onLocalWrite: () {}).createHabit(
      title: 'Sport',
    );
    await HabitLogRepository(db, onLocalWrite: () {})
        .logCompletion(habitId: habitId, day: LocalDay.now());

    final l10n = await pumpHome(tester);

    expect(find.text(l10n.homeProgressSummary(1, 1)), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('with neither a task nor a widget the day really is empty', (
    tester,
  ) async {
    final l10n = await pumpHome(tester);

    expect(find.text(l10n.homeNothingPlanned), findsOneWidget);
    expect(find.text('0/0'), findsOneWidget);
    await unmount(tester);
  });
}
