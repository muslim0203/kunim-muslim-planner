// Regression tests for a theme bug that hid buttons on real devices.
//
// `FilledButton.styleFrom(minimumSize: Size.fromHeight(48))` looks like it
// sets a minimum *height*, but `Size.fromHeight` is defined as
// `Size(double.infinity, height)` — so it also demands an infinite minimum
// *width*. Inside a `Row` that overflows the row, collapses any `Spacer` and
// pushes later children off-screen. On the Pixel 4 emulator it made the task
// editor's Save button unreachable, so a task could never be created.
//
// The widget tests never caught it because they build a plain `MaterialApp`
// with the default theme instead of `KunimTheme`.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/app/theme/app_theme.dart';
import 'package:kunim/app/theme/tokens.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/tasks/presentation/tasks_screen.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

ButtonStyle? _styleOf(ThemeData theme, String which) => switch (which) {
  'filled' => theme.filledButtonTheme.style,
  'elevated' => theme.elevatedButtonTheme.style,
  'outlined' => theme.outlinedButtonTheme.style,
  _ => null,
};

void main() {
  group('button themes keep a finite minimum width', () {
    for (final theme in <(String, ThemeData)>[
      ('light', KunimTheme.light),
      ('dark', KunimTheme.dark),
    ]) {
      for (final which in const ['filled', 'elevated', 'outlined']) {
        test('${theme.$1} / $which', () {
          final style = _styleOf(theme.$2, which);
          final size = style?.minimumSize?.resolve(<WidgetState>{});
          expect(size, isNotNull, reason: '$which button has no minimumSize');
          expect(
            size!.height,
            kMinTouchTarget,
            reason: 'the accessibility minimum height must stay 48',
          );
          expect(
            size.width.isFinite,
            isTrue,
            reason:
                'an infinite minimum width overflows every Row the button sits '
                'in — use Size(0, kMinTouchTarget), not Size.fromHeight(...)',
          );
        });
      }
    }
  });

  testWidgets(
    'task editor actions stay on screen at phone size with the real theme',
    (tester) async {
      // Pixel 4: 1080x2280 at dpr 2.75 => 392.7 x 829.1 logical pixels.
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      final db = AppDatabase.withExecutor(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            syncTriggerSchedulerProvider.overrideWithValue(
              SyncTriggerScheduler(runSync: ({bool force = false}) async {}),
            ),
          ],
          child: MaterialApp(
            theme: KunimTheme.light,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TasksScreen(),
          ),
        ),
      );
      await _pumpFrames(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await _pumpFrames(tester);

      final context = tester.element(find.byType(Scaffold).first);
      final l10n = AppLocalizations.of(context);

      final save = find.widgetWithText(FilledButton, l10n.actionSave);
      expect(save, findsOneWidget);

      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final rect = tester.getRect(save);

      expect(
        rect.left >= 0 && rect.right <= screen.width,
        isTrue,
        reason: 'Save is off-screen horizontally: $rect in $screen',
      );
      expect(
        rect.top >= 0 && rect.bottom <= screen.height,
        isTrue,
        reason: 'Save is off-screen vertically: $rect in $screen',
      );

      // And it must actually be tappable where it is drawn.
      await tester.tap(save, warnIfMissed: true);
      await _pumpFrames(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 3; i++) {
        await tester.pump(Duration.zero);
      }
    },
  );
}
