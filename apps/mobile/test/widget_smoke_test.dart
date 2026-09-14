import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kunim/app/app.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    // Home now reads real providers, so the app needs a database. An
    // in-memory one keeps the smoke test hermetic.
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('launches to the Home screen in Uzbek with 5 nav destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // The real provider calls scheduler.start(), which arms a 5-minute
          // timer and a connectivity listener; a widget test then fails with
          // "A Timer is still pending". Hand it a scheduler nobody starts.
          syncTriggerSchedulerProvider.overrideWithValue(
            SyncTriggerScheduler(runSync: ({bool force = false}) async {}),
          ),
        ],
        child: const KunimApp(),
      ),
    );
    // Not pumpAndSettle: a CircularProgressIndicator animates forever, so
    // pumpAndSettle would time out if any section were still loading.
    // Bounded pumps let the Drift streams deliver their first (empty) value.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final BuildContext context = tester.element(find.byType(Scaffold).first);
    final l10n = AppLocalizations.of(context);

    // Uzbek is the primary language, independent of the device locale.
    expect(Localizations.localeOf(context), const Locale('uz'));

    // All five bottom-nav destinations are present.
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(l10n.navHome), findsOneWidget);
    expect(find.text(l10n.navDay), findsOneWidget);
    expect(find.text(l10n.navStats), findsOneWidget);
    expect(find.text(l10n.navAi), findsOneWidget);
    expect(find.text(l10n.navSettings), findsOneWidget);

    // Home renders its phase-2 blocks. With an empty database each one shows
    // its empty state rather than a spinner, an error or sample data.
    expect(find.text(l10n.homeProgress), findsOneWidget);
    expect(find.text(l10n.homeNothingPlanned), findsOneWidget);
    expect(find.text(l10n.homeMainTasks), findsOneWidget);
    expect(find.text(l10n.homeChooseTopThree), findsOneWidget);

    // The habits block sits below the fold; bring it into view first.
    await tester.scrollUntilVisible(
      find.text(l10n.habitEmptyState),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.homeTodaysHabits), findsOneWidget);
    expect(find.text(l10n.habitEmptyState), findsOneWidget);

    // Unmount so ProviderScope disposes the Drift stream subscriptions.
    // Closing them schedules zero-duration timers inside drift's
    // StreamQueryStore.markAsClosed; the binding fails the test with
    // "A Timer is still pending" unless they are allowed to fire, so pump
    // a few more frames after the tree is gone.
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 3; i++) {
      await tester.pump(Duration.zero);
    }
  });
}
