// Layout regressions across every language, text scale and theme.
//
// The real Manrope font is loaded so text widths are realistic; the default
// test font draws every glyph as a full-em square and would report overflows
// that never happen on a device. Uzbek Cyrillic runs on the platform font in
// the app (see KunimTheme.lightSystemFont), so Roboto is loaded from the
// Flutter SDK for it; without the SDK fonts it falls back to Manrope.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/app.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/app/theme/app_theme.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/settings/app_settings.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/ai/presentation/ai_screen.dart';
import 'package:kunim/features/account/presentation/account_screen.dart';
import 'package:kunim/features/family/presentation/family_screen.dart';
import 'package:kunim/features/goals/presentation/goal_detail_screen.dart';
import 'package:kunim/features/goals/presentation/goals_screen.dart';
import 'package:kunim/features/health/presentation/health_screen.dart';
import 'package:kunim/features/home/presentation/home_screen.dart';
import 'package:kunim/features/mood/presentation/mood_screen.dart';
import 'package:kunim/features/notifications/presentation/notifications_screen.dart';
import 'package:kunim/features/prayer/presentation/prayer_screen.dart';
import 'package:kunim/features/settings/presentation/settings_screen.dart';
import 'package:kunim/features/sleep/presentation/sleep_screen.dart';
import 'package:kunim/features/stats/presentation/stats_screen.dart';

const _phone = Size(1080, 2280);
const _phoneDpr = 2.75;

/// Uzbek Cyrillic renders on the platform font (Roboto on Android) in the
/// app, because Manrope lacks some of its letters. Load Roboto from the
/// Flutter SDK so its widths are realistic here; if it is not available,
/// Uzbek Cyrillic falls back to Manrope and the nav-label check skips it.
var _robotoLoaded = false;

Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final loader = FontLoader('Roboto');
  var added = false;
  for (final weight in const ['regular', 'medium', 'bold']) {
    final file = File(
      '$root/bin/cache/artifacts/material_fonts/roboto-$weight.ttf',
    );
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    added = true;
  }
  if (!added) return;
  await loader.load();
  _robotoLoaded = true;
}

/// Text laid out shorter than it needs, i.e. silently clipped because a
/// parent gave it too little height. Flutter does not report this as an
/// overflow error, so it is measured explicitly.
///
/// When [strict] (normal and moderately enlarged text), a word broken in the
/// middle or text cut off with an ellipsis also counts. At 200% a long word
/// cannot always fit a phone line, and the platform wraps it the same way.
List<String> _clippedText(WidgetTester tester, {required bool strict}) {
  final problems = <String>[];
  for (final paragraph
      in tester.allRenderObjects.whereType<RenderParagraph>()) {
    if (!paragraph.attached || !paragraph.hasSize || paragraph.size.isEmpty) {
      continue;
    }
    final maxWidth = paragraph.constraints.maxWidth;
    if (!maxWidth.isFinite) continue;
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textAlign: paragraph.textAlign,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '…' : null,
      locale: paragraph.locale,
      strutStyle: paragraph.strutStyle,
      textWidthBasis: paragraph.textWidthBasis,
      textHeightBehavior: paragraph.textHeightBehavior,
    )..layout(maxWidth: maxWidth);
    final root = paragraph.text;
    if (strict &&
        root is TextSpan &&
        root.children == null &&
        root.text != null) {
      // A single word wider than its line is broken mid-word by the engine.
      for (final word in root.text!.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final wordPainter = TextPainter(
          text: TextSpan(text: word, style: root.style),
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
          locale: paragraph.locale,
          maxLines: 1,
        )..layout();
        if (wordPainter.width > maxWidth + 0.5) {
          problems.add('word split "$word"');
        }
        wordPainter.dispose();
      }
    }
    if (strict && paragraph.didExceedMaxLines) {
      final plain = paragraph.text.toPlainText();
      problems.add(
        'truncated text "${plain.length > 30 ? plain.substring(0, 30) : plain}"',
      );
    }
    if (painter.height > paragraph.size.height + 1) {
      final plain = paragraph.text.toPlainText();
      problems.add(
        'clipped text "${plain.length > 30 ? plain.substring(0, 30) : plain}"',
      );
    }
    painter.dispose();
  }
  return problems;
}

bool _usesSystemFont(AppLanguage language) =>
    language == AppLanguage.uzCyrl && _robotoLoaded;

Future<void> _pumpFrames(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 3; i++) {
    await tester.pump(Duration.zero);
  }
}

ProviderScope _scope({
  required AppDatabase db,
  required AppSettings settings,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      syncTriggerSchedulerProvider.overrideWithValue(
        SyncTriggerScheduler(runSync: ({bool force = false}) async {}),
      ),
      initialAppSettingsProvider.overrideWithValue(settings),
    ],
    child: child,
  );
}

/// Hosts a single screen with the app's themes, following the settings
/// provider exactly like `KunimApp` does.
Widget _host({
  required AppDatabase db,
  required AppSettings settings,
  required double textScale,
  required Widget screen,
}) {
  return _scope(
    db: db,
    settings: settings,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(appSettingsProvider);
        return MaterialApp(
          theme: _usesSystemFont(current.language)
              ? KunimTheme.lightSystemFont
              : KunimTheme.light,
          darkTheme: _usesSystemFont(current.language)
              ? KunimTheme.darkSystemFont
              : KunimTheme.dark,
          themeMode: current.themeMode,
          locale: current.language.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: screen,
        );
      },
    ),
  );
}

void main() {
  setUpAll(() async {
    final manrope = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope-VariableFont_wght.ttf'));
    await manrope.load();
    await _loadRoboto();
  });

  final screens = <String, Widget Function()>{
    'home': () => const HomeScreen(),
    'stats': () => const StatsScreen(),
    'ai': () => const AiScreen(),
    'settings': () => const SettingsScreen(),
    'prayer': () => const PrayerScreen(),
    'notifications': () => const NotificationsScreen(),
    'mood': () => const MoodScreen(),
    'health': () => const HealthScreen(),
    'sleep': () => const SleepScreen(),
    'family': () => const FamilyScreen(),
    'account': () => const AccountScreen(),
    'goals': () => const GoalsScreen(),
    'goal-missing': () => const GoalDetailScreen(goalId: 'missing'),
  };

  for (final screen in screens.entries) {
    testWidgets('${screen.key} never overflows in any language, scale or theme',
        (tester) async {
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = _phoneDpr;
      addTearDown(tester.view.reset);

      final failures = <String>[];
      for (final language in AppLanguage.values) {
        for (final scale in const [1.0, 1.3, 2.0]) {
          for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
            final db = AppDatabase.withExecutor(NativeDatabase.memory());
            final errors = <String>[];
            final previous = FlutterError.onError;
            FlutterError.onError = (details) {
              errors.add(details.exceptionAsString().split('\n').first);
            };
            try {
              await tester.pumpWidget(
                _host(
                  db: db,
                  settings: AppSettings(language: language, themeMode: mode),
                  textScale: scale,
                  screen: screen.value(),
                ),
              );
              await _pumpFrames(tester);
              errors.addAll(
                _clippedText(tester, strict: scale <= 1.3),
              );
              // Scroll to the end so lazily built content is laid out too.
              final scrollable = find.byType(Scrollable);
              if (scrollable.evaluate().isNotEmpty) {
                await tester.drag(scrollable.first, const Offset(0, -6000));
                await _pumpFrames(tester);
              }
              errors.addAll(
                _clippedText(tester, strict: scale <= 1.3),
              );
              await _unmount(tester);
            } finally {
              FlutterError.onError = previous;
              await db.close();
            }
            if (errors.isNotEmpty) {
              failures.add('${language.code} x$scale ${mode.name}: '
                  '${errors.toSet().join(' | ')}');
            }
          }
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }

  testWidgets('bottom navigation labels stay on one line in every language',
      (tester) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = _phoneDpr;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final failures = <String>[];
    for (final language in AppLanguage.values) {
      // Without Roboto the app's Uzbek Cyrillic font cannot be measured.
      if (language == AppLanguage.uzCyrl && !_robotoLoaded) continue;
      for (final scale in const [1.0, 2.0]) {
        final db = AppDatabase.withExecutor(NativeDatabase.memory());
        // Scale at the platform level: KunimApp builds its own MediaQuery
        // from the view, so a MediaQuery wrapped around it would be ignored.
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpWidget(
          _scope(
            db: db,
            settings:
                AppSettings(language: language, themeMode: ThemeMode.light),
            child: const KunimApp(),
          ),
        );
        await _pumpFrames(tester);

        final context = tester.element(find.byType(NavigationBar));
        final l10n = AppLocalizations.of(context);
        for (final label in [
          l10n.navHome,
          l10n.navDay,
          l10n.navStats,
          l10n.navAi,
          l10n.navSettings,
        ]) {
          final labelFinder = find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          );
          for (final element in labelFinder.evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            final singleLine = TextPainter(
              text: paragraph.text,
              textDirection: paragraph.textDirection,
              textScaler: paragraph.textScaler,
              maxLines: 1,
            )..layout();
            if (paragraph.size.height > singleLine.height + 0.5) {
              failures.add('${language.code} x$scale "$label" wraps');
            }
            singleLine.dispose();
          }
        }
        await _unmount(tester);
        await db.close();
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  testWidgets('switching theme at runtime recolours the life-area tiles',
      (tester) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = _phoneDpr;
    addTearDown(tester.view.reset);

    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      _host(
        db: db,
        settings: AppSettings.defaults.copyWith(themeMode: ThemeMode.light),
        textScale: 1,
        screen: const HomeScreen(),
      ),
    );
    await _pumpFrames(tester);

    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)));
    Color tileColor() {
      final material = find
          .ancestor(
            of: find.text(l10n.modulePrayer),
            matching: find.byType(Material),
          )
          .first;
      return tester.widget<Material>(material).color!;
    }

    expect(tileColor(), KunimTheme.light.colorScheme.surfaceContainerHigh);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    await container
        .read(appSettingsProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    await _pumpFrames(tester, 12);

    expect(tileColor(), KunimTheme.dark.colorScheme.surfaceContainerHigh);

    await _unmount(tester);
  });
}
