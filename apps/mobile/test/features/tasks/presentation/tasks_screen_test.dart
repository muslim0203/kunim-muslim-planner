import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/tasks/presentation/tasks_screen.dart';

/// Pumps a bounded number of frames. Not `pumpAndSettle`: a
/// `CircularProgressIndicator` animates forever, so settling never happens
/// while any section is still loading.
Future<void> pumpFrames(WidgetTester tester, [int frames = 5]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Unmounts the tree and drains the zero-duration timers drift schedules in
/// `StreamQueryStore.markAsClosed`, which otherwise fail the test with
/// "A Timer is still pending".
Future<void> teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 3; i++) {
    await tester.pump(Duration.zero);
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget harness() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // The real provider calls scheduler.start(), arming a 5-minute
        // timer and a connectivity listener.
        syncTriggerSchedulerProvider.overrideWithValue(
          SyncTriggerScheduler(runSync: ({bool force = false}) async {}),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: TasksScreen(),
      ),
    );
  }

  testWidgets('shows the empty state when there are no tasks', (tester) async {
    await tester.pumpWidget(harness());
    await pumpFrames(tester);

    final context = tester.element(find.byType(Scaffold).first);
    final l10n = AppLocalizations.of(context);
    expect(find.text(l10n.taskEmptyState), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('creating a task through the editor shows it in the list', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await pumpFrames(tester);

    final context = tester.element(find.byType(Scaffold).first);
    final l10n = AppLocalizations.of(context);

    await tester.tap(find.byType(FloatingActionButton));
    await pumpFrames(tester);

    await tester.enterText(
      find.widgetWithText(TextField, l10n.taskTitleLabel),
      'Qur\'on o\'qish',
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n.actionSave));
    await pumpFrames(tester, 8);

    expect(find.text('Qur\'on o\'qish'), findsOneWidget);
    expect(find.text(l10n.taskEmptyState), findsNothing);

    await teardownTree(tester);
  });

  testWidgets('ticking the checkbox strikes the task through', (tester) async {
    await tester.pumpWidget(harness());
    await pumpFrames(tester);

    final context = tester.element(find.byType(Scaffold).first);
    final l10n = AppLocalizations.of(context);

    await tester.tap(find.byType(FloatingActionButton));
    await pumpFrames(tester);
    await tester.enterText(
      find.widgetWithText(TextField, l10n.taskTitleLabel),
      'Ertalabki mashq',
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n.actionSave));
    await pumpFrames(tester, 8);

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(find.byType(Checkbox));
    await pumpFrames(tester, 8);

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await teardownTree(tester);
  });
}
