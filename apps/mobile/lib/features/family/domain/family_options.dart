/// Vocabulary and bounds for family entries. Codes are stored and synced;
/// labels come from the ARB files.
abstract final class FamilyOptions {
  static const int maxMinutes = 24 * 60;

  /// Activities offered on the family screen, in display order.
  static const List<String> activities = [
    'talk',
    'meal',
    'walk',
    'call',
    'help',
    'visit',
    'play',
    'reading',
  ];
}
