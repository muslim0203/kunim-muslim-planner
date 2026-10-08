/// The read-only Qur'an data, as the reader needs it.
///
/// Everything here comes from `assets/db/quran.sqlite`, built by
/// `packages/content_tools/build_quran_db.py` from the Tanzil Uthmani text
/// and Tanzil's own metadata. The Arabic is carried verbatim: nothing in this
/// layer edits, normalises or re-spells a single letter of it, and the only
/// thing the app adds on screen is the ayah-number marker between verses.
library;

enum Revelation { meccan, medinan }

class Surah {
  const Surah({
    required this.number,
    required this.ayahCount,
    required this.nameAr,
    required this.nameLatin,
    required this.nameEn,
    required this.revelation,
    required this.revelationOrder,
    required this.rukuCount,
    required this.startPage,
  });

  /// 1..114, in mushaf order.
  final int number;
  final int ayahCount;

  /// The surah's own Arabic name.
  final String nameAr;

  /// Transliterated ("Al-Baqara") and translated ("The Cow") names, both as
  /// Tanzil spells them.
  final String nameLatin;
  final String nameEn;
  final Revelation revelation;
  final int revelationOrder;
  final int rukuCount;

  /// The mushaf page this surah opens on.
  final int startPage;
}

class Ayah {
  const Ayah({
    required this.id,
    required this.surah,
    required this.number,
    required this.text,
    required this.page,
    required this.juz,
    required this.quarter,
    required this.isSajda,
    this.basmalaWords = 0,
  });

  /// 1..6236, in mushaf order — the stable key for a position.
  final int id;
  final int surah;

  /// The ayah's number inside its surah.
  final int number;

  /// Uthmani text, exactly as Tanzil publishes it.
  final String text;
  final int page;
  final int juz;

  /// 1..240: eight quarters to a hizb, two hizbs to a juz.
  final int quarter;
  final bool isSajda;

  /// How many of this ayah's leading words are the basmala. Tanzil carries it
  /// inside the first ayah of every surah that has one; the mushaf gives it a
  /// line of its own, so the reader skips these words on the ayah's own line
  /// and draws them on the basmala line instead.
  final int basmalaWords;

  /// "2:255" — the reference people actually quote.
  String get reference => '$surah:$number';
}

/// What the print puts on one line.
enum LineKind {
  /// Words of the Qur'an.
  ayah,

  /// The surah's name, in its own frame.
  surah,

  /// The basmala that opens a surah.
  basmala,
}

/// One token of a printed line: a word, or the marker that closes an ayah.
class MushafToken {
  const MushafToken({
    required this.text,
    required this.ayahId,
    required this.ayahNumber,
    this.isEndMarker = false,
  });

  final String text;
  final int ayahId;
  final int ayahNumber;
  final bool isEndMarker;
}

/// One of the fifteen lines of a printed page.
class MushafLine {
  const MushafLine({
    required this.number,
    required this.kind,
    this.surah,
    this.tokens = const [],
  });

  /// 1..15, top to bottom.
  final int number;
  final LineKind kind;

  /// The surah a heading or basmala line belongs to.
  final int? surah;

  /// The words on an ayah line, right to left.
  final List<MushafToken> tokens;
}

/// One page of the 604-page Madinah mushaf.
class QuranPage {
  const QuranPage({
    required this.number,
    required this.juz,
    required this.ayahs,
    this.lines = const [],
  });

  final int number;
  final int juz;

  /// In mushaf order. A page always has at least one ayah.
  final List<Ayah> ayahs;

  /// The page as it is printed, line by line. Empty when the database has no
  /// layout, in which case the reader falls back to flowing the text.
  final List<MushafLine> lines;

  /// The surahs that appear on this page, in order — a page can straddle two.
  List<int> get surahNumbers {
    final seen = <int>[];
    for (final ayah in ayahs) {
      if (seen.isEmpty || seen.last != ayah.surah) seen.add(ayah.surah);
    }
    return seen;
  }
}

class Juz {
  const Juz({
    required this.number,
    required this.firstAyahId,
    required this.lastAyahId,
    required this.startPage,
  });

  final int number;
  final int firstAyahId;
  final int lastAyahId;
  final int startPage;
}

/// Where the text came from and on what terms — shown in the reader, because
/// Tanzil's terms require the source to be named and linked wherever the text
/// is used.
class QuranEdition {
  const QuranEdition({
    required this.edition,
    required this.attribution,
    required this.license,
    required this.sourceUrl,
    required this.textSha256,
  });

  final String edition;
  final String attribution;
  final String license;
  final String sourceUrl;

  /// Digest of the source text the database was built from: the same file
  /// always produces the same one, so a tampered build is visible.
  final String textSha256;
}

/// Where the reader left off. Page-level on purpose: that is what a reader
/// remembers about a printed mushaf too.
class QuranPosition {
  const QuranPosition({required this.page, this.ayahId});

  static const QuranPosition start = QuranPosition(page: 1);

  final int page;

  /// The ayah last marked on that page, when there is one.
  final int? ayahId;
}

/// The mushaf's own bounds, so nothing has to hard-code them twice.
abstract final class Mushaf {
  static const int pageCount = 604;
  static const int surahCount = 114;
  static const int juzCount = 30;
  static const int ayahCount = 6236;

  static int clampPage(int page) => page.clamp(1, pageCount);
}
