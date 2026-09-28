// The home grid: life areas and today's habits as one set of widgets.
//
// Rows are read back with one-shot queries, never `watch().first` (a Drift
// stream inside `testWidgets`' fake-async zone waits on timers that only
// advance when the test pumps).
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/habits/application/habits_today_provider.dart';
import 'package:kunim/features/habits/data/habit_repository.dart';
import 'package:kunim/features/habits/domain/habit_kind.dart';
import 'package:kunim/features/habits/presentation/habit_kind_labels.dart';
import 'package:kunim/features/home/presentation/widget_grid.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<AppLocalizations> pumpGrid(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
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
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: HomeWidgetGrid(
                  habits: ref.watch(allHabitsWithTodayProvider),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
    return AppLocalizations.of(tester.element(find.byType(HomeWidgetGrid)));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 3);
  }

  Future<String> seedWidget({
    String title = 'Kitob o‘qish',
    HabitKind kind = HabitKind.book,
    int target = 10,
    int? reminderMinutes,
  }) {
    return HabitRepository(db, onLocalWrite: () {}).createHabit(
      title: title,
      kind: kind,
      targetCount: target,
      reminderMinutes: reminderMinutes,
    );
  }

  Future<List<HabitLog>> logs() => db.select(db.habitLogs).get();

  testWidgets('a widget shows today’s progress and the time of its task', (
    tester,
  ) async {
    await seedWidget(reminderMinutes: 450);

    final l10n = await pumpGrid(tester);

    expect(find.text('Kitob o‘qish'), findsOneWidget);
    expect(find.text('0/10'), findsOneWidget);
    expect(find.text('7:30'), findsOneWidget);
    // The life areas are still one tap away, next to the widgets.
    expect(find.text(l10n.homeAllModules), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a widget with no time set shows its daily amount instead', (
    tester,
  ) async {
    await seedWidget(title: 'Zikr', kind: HabitKind.zikr, target: 1);

    final l10n = await pumpGrid(tester);

    expect(find.text(habitAmount(l10n, HabitKind.zikr, 1)), findsOneWidget);
    expect(find.text('7:30'), findsNothing);
    await unmount(tester);
  });

  testWidgets('tapping a widget does today’s work', (tester) async {
    await seedWidget(title: 'Zikr', kind: HabitKind.zikr, target: 1);
    await pumpGrid(tester);

    await tester.tap(find.text('Zikr'));
    await _pumpFrames(tester);

    final saved = await logs();
    expect(saved, hasLength(1));
    expect(saved.single.count, 1);
    await unmount(tester);
  });

  testWidgets('holding a widget opens its options', (tester) async {
    await seedWidget(title: 'Zikr', kind: HabitKind.zikr, target: 1);
    final l10n = await pumpGrid(tester);

    await tester.longPress(find.text('Zikr'));
    await _pumpFrames(tester);

    expect(find.text(l10n.habitLogToday), findsOneWidget);
    expect(find.text(l10n.habitEdit), findsOneWidget);
    expect(await logs(), isEmpty);
    await unmount(tester);
  });

  testWidgets('with nothing set up yet the grid asks for a first widget', (
    tester,
  ) async {
    final l10n = await pumpGrid(tester);

    expect(find.text(l10n.homeWidgetsEmpty), findsOneWidget);
    expect(find.text(l10n.homeWidgetAdd), findsOneWidget);
    expect(find.text(l10n.homeAllModules), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the catalogue opens the editor set up for the chosen kind', (
    tester,
  ) async {
    final l10n = await pumpGrid(tester);

    await tester.tap(find.text(l10n.homeWidgetAdd));
    await _pumpFrames(tester);
    expect(find.text(l10n.habitCatalogTitle), findsOneWidget);

    await tester.tap(find.text(l10n.habitKindBook));
    await _pumpFrames(tester);

    // The editor starts from the kind: its name and its own daily amount.
    expect(find.text(l10n.habitNew), findsOneWidget);
    expect(
      find.widgetWithText(TextField, l10n.habitKindBook),
      findsOneWidget,
    );
    expect(
      find.text(habitAmount(l10n, HabitKind.book, HabitKind.book.dailyTarget)),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('the editor shows a widget’s time and can clear it', (
    tester,
  ) async {
    final id = await seedWidget(reminderMinutes: 450);
    final l10n = await pumpGrid(tester);

    await tester.longPress(find.text('Kitob o‘qish'));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.habitEdit));
    await _pumpFrames(tester);

    expect(find.widgetWithText(OutlinedButton, '7:30'), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.habitTimeClear));
    await _pumpFrames(tester);
    expect(find.widgetWithText(OutlinedButton, l10n.habitTimeNone),
        findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, l10n.logSave));
    await _pumpFrames(tester);

    final saved =
        await (db.select(db.habits)..where((h) => h.id.equals(id))).getSingle();
    expect(saved.reminderMinutes, isNull);
    await unmount(tester);
  });
}
