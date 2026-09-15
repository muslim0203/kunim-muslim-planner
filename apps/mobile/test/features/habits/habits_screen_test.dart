// Habits: creating one with a schedule, checking it off for today, changing
// its daily target, and deleting it.
//
// Rows are read back with one-shot queries, never `watch().first` (see
// `daily_log_screens_test.dart` for why).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/habits/data/habit_repository.dart';
import 'package:kunim/features/habits/domain/habit_schedule.dart';
import 'package:kunim/features/habits/presentation/habits_screen.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<AppLocalizations> pumpHabits(WidgetTester tester) async {
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
          home: const HabitsScreen(),
        ),
      ),
    );
    await _pumpFrames(tester);
    return AppLocalizations.of(tester.element(find.byType(HabitsScreen)));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 3);
  }

  Future<String> seedHabit({String title = 'Qur’on o‘qish'}) =>
      HabitRepository(db, onLocalWrite: () {}).createHabit(title: title);

  Future<List<Habit>> liveHabits() =>
      (db.select(db.habits)..where((h) => h.deletedAt.isNull())).get();

  Future<List<HabitLog>> liveLogs(String habitId) => (db.select(db.habitLogs)
        ..where((l) => l.habitId.equals(habitId) & l.deletedAt.isNull()))
      .get();

  testWidgets('creates a habit on chosen weekdays', (tester) async {
    final l10n = await pumpHabits(tester);
    expect(find.text(l10n.habitEmptyState), findsOneWidget);

    await tester.tap(find.text(l10n.habitNew));
    await _pumpFrames(tester);
    await tester.enterText(
      find.widgetWithText(TextField, l10n.habitNameLabel),
      'Sport',
    );
    await tester.tap(find.text(l10n.habitScheduleSpecificWeekdays));
    await _pumpFrames(tester);

    // No day picked yet: saving is not possible.
    final save = find.widgetWithText(FilledButton, l10n.logSave);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(find.text(l10n.habitWeekdaysRequired), findsOneWidget);

    await tester.tap(find.text(l10n.calWeekdayMondayShort));
    await tester.tap(find.text(l10n.calWeekdayFridayShort));
    await _pumpFrames(tester);
    await tester.tap(save);
    await _pumpFrames(tester);

    final habit = (await liveHabits()).single;
    expect(habit.title, 'Sport');
    expect(
      HabitSchedule.fromJson(habit.frequency),
      const HabitSchedule.specificWeekdays({DateTime.monday, DateTime.friday}),
    );
    expect(find.text('Sport'), findsOneWidget);
    expect(
      find.text(
        '${l10n.calWeekdayMondayShort}, ${l10n.calWeekdayFridayShort}',
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('checks a habit off for today and undoes it', (tester) async {
    final habitId = await seedHabit();
    final l10n = await pumpHabits(tester);

    await tester.tap(find.byTooltip(l10n.habitLogToday));
    await _pumpFrames(tester);
    expect((await liveLogs(habitId)).single.count, 1);
    expect(find.byTooltip(l10n.habitUndoToday), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.habitUndoToday));
    await _pumpFrames(tester);
    expect(await liveLogs(habitId), isEmpty);
    expect(find.byTooltip(l10n.habitLogToday), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('raises the daily target from the editor', (tester) async {
    await seedHabit();
    final l10n = await pumpHabits(tester);

    await tester.tap(find.text('Qur’on o‘qish'));
    await _pumpFrames(tester);
    // A frame between taps, as for a real user: each tap acts on the value
    // the stepper last showed.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip(l10n.habitIncrease).last);
      await _pumpFrames(tester, 2);
    }
    expect(find.text(l10n.habitTargetPerDay(3)), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l10n.logSave));
    await _pumpFrames(tester);

    expect((await liveHabits()).single.targetCount, 3);
    expect(find.text('0/3'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('deleting a habit asks first', (tester) async {
    await seedHabit();
    final l10n = await pumpHabits(tester);

    await tester.tap(find.text('Qur’on o‘qish'));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.logDelete));
    await _pumpFrames(tester);
    expect(find.text(l10n.habitArchiveConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.logDelete).last);
    // Enough frames for the archive write to commit before reading it back.
    await _pumpFrames(tester, 20);

    expect(await liveHabits(), isEmpty);
    expect(find.text(l10n.habitEmptyState), findsOneWidget);
    await unmount(tester);
  });
}
