// The bundled mushaf, read the way the app reads it.
//
// These run against the very file that ships in `assets/db/quran.sqlite`, so
// a rebuilt or truncated database fails here rather than on a reader's phone.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/quran/data/quran_asset_database.dart';
import 'package:kunim/features/quran/data/quran_repository.dart';
import 'package:kunim/features/quran/domain/quran_models.dart';

void main() {
  late QuranAssetDatabase database;
  late QuranRepository quran;

  setUp(() {
    database = QuranAssetDatabase.fromFile('assets/db/quran.sqlite');
    quran = QuranRepository(database);
  });
  tearDown(() => database.close());

  test('the asset ships with the app', () {
    expect(File('assets/db/quran.sqlite').existsSync(), isTrue);
  });

  test('the mushaf is whole', () async {
    final surahs = await quran.surahs();
    final juzs = await quran.juzs();

    expect(surahs, hasLength(Mushaf.surahCount));
    expect(juzs, hasLength(Mushaf.juzCount));
    expect(surahs.first.number, 1);
    expect(surahs.last.number, Mushaf.surahCount);
  });

  test('every one of the 604 pages has text on it', () async {
    var ayahs = 0;
    for (var number = 1; number <= Mushaf.pageCount; number++) {
      final page = await quran.page(number);
      expect(page.ayahs, isNotEmpty, reason: 'page $number is empty');
      expect(page.number, number);
      ayahs += page.ayahs.length;
    }

    expect(ayahs, Mushaf.ayahCount);
  });

  test('the pages are the ones the printed Madinah mushaf has', () async {
    // The page a surah opens on is the plainest way to tell this layout from
    // any other: these are the numbers on the printed page.
    expect(await quran.pageOfSurah(2), 2);
    expect(await quran.pageOfSurah(18), 293);
    expect(await quran.pageOfSurah(36), 440);
    expect(await quran.pageOfSurah(78), 582);
    expect(await quran.pageOfSurah(114), 604);
    expect(await quran.pageOfAyah(surah: 2, ayah: 255), 42);
  });

  test('a juz starts where the mushaf starts it', () async {
    final juzs = await quran.juzs();

    expect(juzs.first.startPage, 1);
    expect(juzs[29].number, 30);
    expect(juzs[29].startPage, 582);
    expect(juzs.last.lastAyahId, Mushaf.ayahCount);
  });

  test('an ayah carries its place in the mushaf', () async {
    final page = await quran.page(42);
    final kursi = page.ayahs.firstWhere(
      (ayah) => ayah.surah == 2 && ayah.number == 255,
    );

    expect(kursi.reference, '2:255');
    expect(kursi.juz, 3);
    expect(kursi.text.trim(), kursi.text, reason: 'stored text was padded');
    expect(kursi.text, isNotEmpty);
  });

  test('the fifteen sajda ayahs are marked', () async {
    var marked = 0;
    for (var number = 1; number <= Mushaf.pageCount; number++) {
      final page = await quran.page(number);
      marked += page.ayahs.where((ayah) => ayah.isSajda).length;
    }

    expect(marked, 15);
  });

  test('a page knows which surahs are printed on it', () async {
    // Al-Fatiha ends and Al-Baqara opens on page 2 of the mushaf.
    final page = await quran.page(2);

    expect(page.surahNumbers, contains(2));
    expect(page.juz, 1);
  });

  test('the text carries its source and terms', () async {
    final edition = await quran.edition();

    expect(edition.edition, contains('Uthmani'));
    expect(edition.attribution, contains('Tanzil'));
    expect(edition.sourceUrl, contains('tanzil.net'));
    expect(edition.license, contains('must not be changed'));
    // The digest of the source text: a silent edit of the asset shows up as
    // a mismatch rather than as a quietly different Qur'an.
    expect(edition.textSha256, hasLength(64));
  });

  test('a page is broken into the lines the mushaf prints', () async {
    // The layout is the reason this data exists: a memoriser knows a verse by
    // where it sits on the page.
    final page = await quran.page(2);

    expect(page.lines, hasLength(8));
    expect(page.lines.first.kind, LineKind.surah);
    expect(page.lines.first.surah, 2);
    expect(page.lines[1].kind, LineKind.basmala);
    expect(page.lines[2].kind, LineKind.ayah);
    // Al-Baqara's first line ends inside its second ayah, as it does in print.
    expect(page.lines[2].tokens.first.ayahNumber, 1);
    expect(page.lines[2].tokens.last.ayahNumber, 2);
  });

  test('every page of the mushaf has its printed lines', () async {
    var lines = 0;
    for (var number = 1; number <= Mushaf.pageCount; number++) {
      final page = await quran.page(number);
      expect(page.lines, isNotEmpty, reason: 'page $number has no layout');
      // A printed page holds fifteen lines; the two opening pages hold less.
      expect(page.lines.length, lessThanOrEqualTo(15));
      expect(
        page.lines.map((line) => line.number).toList(),
        List.generate(page.lines.length, (index) => index + 1),
        reason: 'page $number skips a line',
      );
      lines += page.lines.length;
    }

    expect(lines, 9025);
  });

  test('the basmala is left off the ayah line that carries it', () async {
    final page = await quran.page(2);
    final first = page.lines[2].tokens.first;
    final baqara = page.ayahs.firstWhere((ayah) => ayah.number == 1);

    // Tanzil keeps the basmala inside 2:1; the printed line starts after it.
    expect(baqara.basmalaWords, 4);
    expect(baqara.text.split(' ').first, isNot(first.text));
  });

  test('an ayah ends with its own number marker', () async {
    final page = await quran.page(1);
    final markers = [
      for (final line in page.lines)
        for (final token in line.tokens)
          if (token.isEndMarker) token.ayahNumber,
    ];

    // Al-Fatiha's seven ayahs each close on this page.
    expect(markers, [1, 2, 3, 4, 5, 6, 7]);
  });

  test('a page number outside the mushaf is pulled back inside', () async {
    expect((await quran.page(0)).number, 1);
    expect((await quran.page(9000)).number, Mushaf.pageCount);
  });
}
