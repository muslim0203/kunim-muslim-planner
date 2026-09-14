/// Vocabulary and bounds for mood entries. The repository validates against
/// these and the screen offers them; codes are what is stored and synced,
/// labels come from the ARB files.
abstract final class MoodOptions {
  static const int minScore = 1;
  static const int maxScore = 5;

  /// Feelings offered on the mood screen, in display order.
  static const List<String> tags = [
    'calm',
    'happy',
    'grateful',
    'energetic',
    'focused',
    'tired',
    'anxious',
    'sad',
    'irritated',
    'stressed',
  ];
}
