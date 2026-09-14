import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/settings/app_settings.dart';
import 'package:kunim/features/ai/presentation/ai_screen.dart';
import 'package:kunim/features/settings/presentation/settings_screen.dart';
import 'package:kunim/shared/widgets/kunim_widgets.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _host(AppDatabase db, Widget screen) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(appSettingsProvider);
        return MaterialApp(
          locale: settings.language.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: screen,
        );
      },
    ),
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('shows the current language and saves a new choice', (
    tester,
  ) async {
    await tester.pumpWidget(_host(db, const SettingsScreen()));
    await _pumpFrames(tester);

    final l10n =
        AppLocalizations.of(tester.element(find.byType(SettingsScreen)));
    expect(find.text(l10n.languageNameUz), findsOneWidget);

    await tester.tap(find.text(l10n.settingsLanguage));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.languageNameRu).last);
    await _pumpFrames(tester);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
    expect(container.read(appSettingsProvider).language, AppLanguage.ru);
    expect((await AppSettingsStore(db).load()).language, AppLanguage.ru);

    // The screen now renders in Russian.
    final ruL10n =
        AppLocalizations.of(tester.element(find.byType(SettingsScreen)));
    expect(find.text(ruL10n.settingsLanguage), findsOneWidget);
  });

  testWidgets('saves a theme choice', (tester) async {
    await tester.pumpWidget(_host(db, const SettingsScreen()));
    await _pumpFrames(tester);

    final l10n =
        AppLocalizations.of(tester.element(find.byType(SettingsScreen)));
    await tester.tap(find.text(l10n.settingsAppearance));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.themeDark).last);
    await _pumpFrames(tester);

    expect((await AppSettingsStore(db).load()).themeMode, ThemeMode.dark);
  });

  testWidgets('unbuilt sections are marked coming soon and ignore taps', (
    tester,
  ) async {
    await tester.pumpWidget(_host(db, const SettingsScreen()));
    await _pumpFrames(tester);

    final l10n =
        AppLocalizations.of(tester.element(find.byType(SettingsScreen)));
    // Privacy is not built yet.
    expect(find.byType(ComingSoonBadge), findsOneWidget);
    // No invented profile data.
    expect(find.text(l10n.settingsGuestName), findsOneWidget);

    await tester.tap(find.text(l10n.settingsPrivacy));
    await _pumpFrames(tester);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('the AI preview cannot be typed into or submitted', (
    tester,
  ) async {
    // Tall enough that the lazily built list lays out every control, so the
    // "no chevron" check below is not satisfied just by tiles off-screen.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(db, const AiScreen()));
    await _pumpFrames(tester);

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.byType(ComingSoonBadge), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });
}
