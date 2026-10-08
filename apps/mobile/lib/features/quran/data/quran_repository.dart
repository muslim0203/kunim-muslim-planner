/// Reads the bundled mushaf: its surahs, its juzs and its 604 pages.
///
/// Every method is a plain query against the read-only asset database. The
/// text is returned exactly as stored; the reader adds nothing to it but the
/// ayah-number marker it draws between verses.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/quran_models.dart';
import 'quran_asset_database.dart';

class QuranRepository {
  QuranRepository(this._database);

  final QuranAssetDatabase _database;

  Future<List<Surah>> surahs() async {
    final db = await _database.open();
    return db
        .select('SELECT * FROM surahs ORDER BY number')
        .map(_surah)
        .toList();
  }

  Future<List<Juz>> juzs() async {
    final db = await _database.open();
    return db.select('SELECT * FROM juzs ORDER BY number').map(_juz).toList();
  }

  /// One page of the mushaf, with the ayahs printed on it.
  Future<QuranPage> page(int number) async {
    final db = await _database.open();
    final page = Mushaf.clampPage(number);
    final rows = db.select(
      'SELECT * FROM ayahs WHERE page = ? ORDER BY id',
      [page],
    );
    if (rows.isEmpty) {
      throw StateError('Mushaf page $page has no ayahs: the database is not '
          'the one build_quran_db.py produces.');
    }
    final ayahs = rows.map(_ayah).toList();
    return QuranPage(
      number: page,
      juz: ayahs.first.juz,
      ayahs: ayahs,
      lines: _linesOf(db, page, ayahs),
    );
  }

  /// The page as the mushaf prints it: fifteen lines, each holding exactly
  /// the words the printed page holds. This is what memorising from a mushaf
  /// depends on — the same words in the same place every time.
  List<MushafLine> _linesOf(Database db, int page, List<Ayah> ayahs) {
    final rows = db.select(
      'SELECT * FROM lines WHERE page = ? ORDER BY line',
      [page],
    );
    if (rows.isEmpty) return const [];

    final byId = {for (final ayah in ayahs) ayah.id: ayah};
    final tokens = {
      for (final ayah in ayahs) ayah.id: _tokensOf(db, ayah),
    };

    final lines = <MushafLine>[];
    for (final row in rows) {
      final kind = switch (row['kind'] as String) {
        'surah' => LineKind.surah,
        'basmala' => LineKind.basmala,
        _ => LineKind.ayah,
      };
      if (kind != LineKind.ayah) {
        lines.add(
          MushafLine(
            number: row['line'] as int,
            kind: kind,
            surah: row['surah'] as int?,
          ),
        );
        continue;
      }

      final firstAyah = row['first_ayah_id'] as int;
      final lastAyah = row['last_ayah_id'] as int;
      final firstPos = row['first_pos'] as int;
      final lastPos = row['last_pos'] as int;
      final onLine = <MushafToken>[];
      for (var id = firstAyah; id <= lastAyah; id++) {
        final ayahTokens = tokens[id];
        if (ayahTokens == null) continue;
        final from = id == firstAyah ? firstPos : 1;
        final to = id == lastAyah ? lastPos : ayahTokens.length;
        for (var pos = from; pos <= to && pos <= ayahTokens.length; pos++) {
          onLine.add(ayahTokens[pos - 1]);
        }
      }
      lines.add(
        MushafLine(
          number: row['line'] as int,
          kind: LineKind.ayah,
          surah: byId[firstAyah]?.surah,
          tokens: onLine,
        ),
      );
    }
    return lines;
  }

  /// An ayah's printed tokens: its words, grouped the way the print groups
  /// them, and then the marker that closes the verse. The basmala that Tanzil
  /// keeps inside a surah's first ayah is left out — the page gives it a line
  /// of its own.
  List<MushafToken> _tokensOf(Database db, Ayah ayah) {
    var words = ayah.text.split(RegExp(r'\s+'))
      ..removeWhere((word) => word.isEmpty);
    if (ayah.basmalaWords > 0 && words.length > ayah.basmalaWords) {
      words = words.sublist(ayah.basmalaWords);
    }

    final grouping = db
        .select(
          'SELECT words FROM ayah_tokens WHERE ayah_id = ? ORDER BY pos',
          [ayah.id],
        )
        .map((row) => row['words'] as int)
        .toList();

    final texts = <String>[];
    if (grouping.isEmpty) {
      texts.addAll(words);
    } else {
      var index = 0;
      for (final count in grouping) {
        texts.add(words.sublist(index, index + count).join(' '));
        index += count;
      }
      if (index < words.length) texts.addAll(words.sublist(index));
    }

    return [
      for (final text in texts)
        MushafToken(text: text, ayahId: ayah.id, ayahNumber: ayah.number),
      MushafToken(
        text: '',
        ayahId: ayah.id,
        ayahNumber: ayah.number,
        isEndMarker: true,
      ),
    ];
  }

  /// The page a surah opens on.
  Future<int> pageOfSurah(int surah) async {
    final db = await _database.open();
    final rows = db.select(
      'SELECT start_page FROM surahs WHERE number = ?',
      [surah],
    );
    return rows.isEmpty ? 1 : rows.first['start_page'] as int;
  }

  /// The page an ayah sits on, for jumping to a reference like 2:255.
  Future<int?> pageOfAyah({required int surah, required int ayah}) async {
    final db = await _database.open();
    final rows = db.select(
      'SELECT page FROM ayahs WHERE surah = ? AND number = ?',
      [surah, ayah],
    );
    return rows.isEmpty ? null : rows.first['page'] as int;
  }

  /// Where the text came from and on what terms.
  Future<QuranEdition> edition() async {
    final db = await _database.open();
    final meta = {
      for (final row in db.select('SELECT key, value FROM meta'))
        row['key'] as String: row['value'] as String,
    };
    return QuranEdition(
      edition: meta['edition'] ?? '',
      attribution: meta['attribution'] ?? '',
      license: meta['license'] ?? '',
      sourceUrl: meta['source_url'] ?? '',
      textSha256: meta['text_sha256'] ?? '',
    );
  }

  static Surah _surah(Row row) => Surah(
        number: row['number'] as int,
        ayahCount: row['ayah_count'] as int,
        nameAr: row['name_ar'] as String,
        nameLatin: row['name_latin'] as String,
        nameEn: row['name_en'] as String,
        revelation: row['revelation'] == 'medinan'
            ? Revelation.medinan
            : Revelation.meccan,
        revelationOrder: row['revelation_order'] as int,
        rukuCount: row['ruku_count'] as int,
        startPage: row['start_page'] as int,
      );

  static Juz _juz(Row row) => Juz(
        number: row['number'] as int,
        firstAyahId: row['first_ayah_id'] as int,
        lastAyahId: row['last_ayah_id'] as int,
        startPage: row['start_page'] as int,
      );

  static Ayah _ayah(Row row) => Ayah(
        id: row['id'] as int,
        surah: row['surah'] as int,
        number: row['number'] as int,
        text: row['text'] as String,
        page: row['page'] as int,
        juz: row['juz'] as int,
        quarter: row['quarter'] as int,
        isSajda: (row['sajda'] as int) == 1,
        basmalaWords: (row['basmala_words'] as int?) ?? 0,
      );
}

final quranRepositoryProvider = Provider<QuranRepository>((ref) {
  return QuranRepository(ref.watch(quranAssetDatabaseProvider));
});
