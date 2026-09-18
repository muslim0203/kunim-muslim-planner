/// What a habit widget tracks, and the defaults its editor starts from.
///
/// [code] is the wire value stored in `habits.kind`; never rename one. A code
/// this build does not know (a newer app version on another device) reads
/// back as [custom], so the habit still works — it just shows as a plain
/// widget instead of a specialised one.
library;

enum HabitKind {
  custom('custom', dailyTarget: 1),
  book('book', dailyTarget: 10, hasTotal: true),
  quran('quran', dailyTarget: 5, hasTotal: true),
  study('study', dailyTarget: 20, hasTotal: true),
  zikr('zikr', dailyTarget: 100),
  sport('sport', dailyTarget: 30),
  water('water', dailyTarget: 8);

  const HabitKind(
    this.code, {
    required this.dailyTarget,
    this.hasTotal = false,
  });

  final String code;

  /// What the editor suggests as the daily amount for a new widget.
  final int dailyTarget;

  /// Whether the widget works towards a total (a book's pages, the ayahs to
  /// memorise): those ask for a total and show a projected finish day.
  final bool hasTotal;

  static HabitKind fromCode(String? code) {
    for (final kind in values) {
      if (kind.code == code) return kind;
    }
    return HabitKind.custom;
  }
}
