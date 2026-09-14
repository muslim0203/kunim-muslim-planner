/// Bounds for sleep entries, matching what the server validates.
abstract final class SleepLimits {
  static const int minQuality = 1;
  static const int maxQuality = 5;

  /// A single night may not be longer than a day.
  static const int maxDurationMin = 24 * 60;
}
