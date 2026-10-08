// The Qur'an index and the mushaf reader, driven against the real bundled
// database (the asset file is opened straight from disk here).
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/quran/data/quran_asset_database.dart';
import 'package:kunim/features/quran/data/quran_position_store.dart';
import 'package:kunim/features/quran/domain/quran_models.dart';
import 'package:kunim/features/quran/presentation/quran_reader_screen.dart';
import 'package:kunim/features/quran/presentation/quran_screen.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late AppDatabase db;
  late QuranAssetDatabase mushaf;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    mushaf = QuranAssetDatabase.fromFile('assets/db/quran.sqlite');
  });
  tearDown(() async {
    mushaf.close();
    await db.close();
  });

  Future<AppLocalizations> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          quranAssetDatabaseProvider.overrideWithValue(mushaf),
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
    // Looked up below the app: `MaterialApp`'s own element sits above
    // the Localizations widget, where there is nothing to find.
    return AppLocalizations.of(tester.element(find.byType(Scaffold).first));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 3);
  }

  testWidgets('the index lists the surahs and names its source', (
    tester,
  ) async {
    final l10n = await pump(tester, const QuranScreen());

    expect(find.text(l10n.quranTitle), findsOneWidget);
    expect(find.text('Al-Faatiha'), findsOneWidget);
    expect(find.text('Al-Baqara'), findsOneWidget);
    // Tanzil's terms: the source is named wherever the text is shown.
    expect(find.textContaining('Tanzil'), findsOneWidget);
    // Nothing has been read yet, so the card invites a start.
    expect(find.text(l10n.quranStart), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a surah opens the mushaf at its own page', (tester) async {
    final l10n = await pump(tester, const QuranScreen());

    await tester.tap(find.text('Al-Kahf'));
    await _pumpFrames(tester, 20);

    // Al-Kahf opens on page 293 of the Madinah mushaf.
    expect(find.text(l10n.quranPageNumber(293)), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the juz tab opens the mushaf where the juz starts', (
    tester,
  ) async {
    final l10n = await pump(tester, const QuranScreen());

    await tester.tap(find.text(l10n.quranJuzs));
    await _pumpFrames(tester, 20);
    // The list is lazy: the last juz is far below the fold.
    await tester.scrollUntilVisible(
      find.text(l10n.quranJuzNumber(30)),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await _pumpFrames(tester, 5);
    await tester.tap(find.text(l10n.quranJuzNumber(30)));
    await _pumpFrames(tester, 20);

    expect(find.text(l10n.quranPageNumber(582)), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the reader shows the page it was opened at', (tester) async {
    final l10n = await pump(
      tester,
      const QuranReaderScreen(initialPage: 604),
    );

    expect(find.text(l10n.quranPageNumber(604)), findsOneWidget);
    expect(find.byType(MushafPageText), findsWidgets);
    // The last page of the mushaf ends the last juz.
    expect(find.text(l10n.quranJuzNumber(30)), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('turning the page is remembered for next time', (tester) async {
    final l10n = await pump(tester, const QuranReaderScreen(initialPage: 100));

    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1200);
    await _pumpFrames(tester, 30);

    // Which way the flick went is the platform's business; what matters is
    // that the page on screen is the page that gets remembered.
    final saved = await QuranPositionStore(db).load();
    expect(saved, isNotNull);
    expect(saved!.page, isNot(100));
    expect((saved.page - 100).abs(), 1);
    expect(find.text(l10n.quranPageNumber(saved.page)), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a remembered page is where the index offers to continue', (
    tester,
  ) async {
    await QuranPositionStore(db).save(const QuranPosition(page: 42));

    final l10n = await pump(tester, const QuranScreen());

    expect(find.text(l10n.quranContinue), findsOneWidget);
    expect(find.text(l10n.quranPageNumber(42)), findsWidgets);
    await unmount(tester);
  });
}
