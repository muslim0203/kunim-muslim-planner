/// Bounds for health entries, matching what the server validates. They guard
/// against typos, not medical ranges.
abstract final class HealthLimits {
  static const int maxWaterMl = 20000;
  static const int maxSteps = 200000;
  static const int maxWorkoutMin = 24 * 60;
  static const int maxCalories = 20000;
  static const double minWeightKg = 20;
  static const double maxWeightKg = 400;
}
