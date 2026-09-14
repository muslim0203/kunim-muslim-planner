// Personal growth: creating a goal from the list, and working with one on
// its detail screen (milestones, progress, deleting).
//
// Rows are read back with one-shot queries, never `watch().first` (see
// `daily_log_screens_test.dart` for why).
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/goals/data/goal_repository.dart';
import 'package:kunim/features/goals/data/milestone_repository.dart';
import 'package:kunim/features/goals/presentation/goal_detail_screen.dart';
import 'package:kunim/features/goals/presentation/goals_screen.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<AppLocalizations> pumpScreen(
    WidgetTester tester,
    Widget screen,
  ) async {
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

  Future<Goal> seedGoal() =>
      GoalRepository(db).createGoal(title: 'Arab tilini o‘rganish');

  Future<Goal> storedGoal(String id) =>
      (db.select(db.goals)..where((g) => g.id.equals(id))).getSingle();

  Future<List<Milestone>> liveMilestones(String goalId) =>
      MilestoneRepository(db).listForGoal(goalId);

  testWidgets('list: creates a goal once it has a title', (tester) async {
    final l10n = await pumpScreen(tester, const GoalsScreen());
    expect(find.text(l10n.goalEmptyState), findsOneWidget);

    await tester.tap(find.text(l10n.goalNew));
    await _pumpFrames(tester);
    final save = find.widgetWithText(FilledButton, l10n.logSave);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, l10n.goalTitleLabel),
      'Kitob o‘qish',
    );
    await _pumpFrames(tester);
    await tester.tap(save);
    await _pumpFrames(tester);

    final goals =
        await (db.select(db.goals)..where((g) => g.deletedAt.isNull())).get();
    expect(goals.single.title, 'Kitob o‘qish');
    expect(goals.single.targetDate, isNull);
    expect(find.text(l10n.goalEmptyState), findsNothing);
    expect(find.text('Kitob o‘qish'), findsOneWidget);
    expect(find.text(l10n.goalNoTargetDate), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('detail: adds a milestone and ticks it off', (tester) async {
    final goal = await seedGoal();
    final l10n = await pumpScreen(tester, GoalDetailScreen(goalId: goal.id));
    expect(find.text(goal.title), findsOneWidget);
    expect(find.text(l10n.goalMilestonesEmpty), findsOneWidget);

    await tester.tap(find.text(l10n.goalAddMilestone));
    await _pumpFrames(tester);
    await tester.enterText(
      find.widgetWithText(TextField, l10n.goalTitleLabel),
      'Alifbo',
    );
    await _pumpFrames(tester);
    await tester.tap(find.widgetWithText(FilledButton, l10n.logSave));
    await _pumpFrames(tester);

    expect((await liveMilestones(goal.id)).single.title, 'Alifbo');
    expect(find.text(l10n.goalMilestonesDoneCount(0, 1)), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await _pumpFrames(tester);

    expect((await liveMilestones(goal.id)).single.completedAt, isNotNull);
    expect(find.text(l10n.goalMilestonesDoneCount(1, 1)), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('detail: the slider saves the progress', (tester) async {
    final goal = await seedGoal();
    final l10n = await pumpScreen(tester, GoalDetailScreen(goalId: goal.id));
    expect(find.text(l10n.goalProgressValue(0)), findsOneWidget);

    await tester.tap(find.byType(Slider));
    await _pumpFrames(tester);

    expect((await storedGoal(goal.id)).progressPercent, 50);
    expect(find.text(l10n.goalProgressValue(50)), findsWidgets);
    await unmount(tester);
  });

  testWidgets('detail: deleting asks first and removes the milestones', (
    tester,
  ) async {
    final goal = await seedGoal();
    await MilestoneRepository(db)
        .createMilestone(goalId: goal.id, title: 'Alifbo');
    final l10n = await pumpScreen(tester, GoalDetailScreen(goalId: goal.id));

    await tester.tap(find.byTooltip(l10n.goalEdit));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.logDelete));
    await _pumpFrames(tester);
    expect(find.text(l10n.goalDeleteConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.logDelete).last);
    await _pumpFrames(tester, 20);

    expect((await storedGoal(goal.id)).deletedAt, isNotNull);
    expect(await liveMilestones(goal.id), isEmpty);
    expect(find.text(l10n.goalNotFound), findsOneWidget);
    await unmount(tester);
  });
}
