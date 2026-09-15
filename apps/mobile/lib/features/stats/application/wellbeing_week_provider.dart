/// Wires the daily log streams (mood, sleep, health, family) and prayer
/// marks into [WellbeingWeek].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../family/application/family_providers.dart';
import '../../health/application/health_providers.dart';
import '../../mood/application/mood_providers.dart';
import '../../prayer/application/prayer_log_providers.dart';
import '../../sleep/application/sleep_providers.dart';
import '../domain/wellbeing_week.dart';
import 'weekly_stats_provider.dart';

final wellbeingWeekProvider = Provider<AsyncValue<WellbeingWeek>>((ref) {
  // The recent-entry streams hold up to 60 days (prayers: two weeks), which
  // always covers the week.
  final moods = ref.watch(recentMoodLogsProvider);
  final sleeps = ref.watch(recentSleepLogsProvider);
  final healths = ref.watch(recentHealthLogsProvider);
  final families = ref.watch(recentFamilyLogsProvider);
  final prayers = ref.watch(recentPrayerLogsProvider);
  final today = ref.watch(statsTodayProvider);

  for (final value in <AsyncValue<Object?>>[
    moods,
    sleeps,
    healths,
    families,
    prayers,
  ]) {
    if (value.hasError) {
      return AsyncValue.error(
        value.error!,
        value.stackTrace ?? StackTrace.current,
      );
    }
  }

  final moodRows = moods.value;
  final sleepRows = sleeps.value;
  final healthRows = healths.value;
  final familyRows = families.value;
  final prayerRows = prayers.value;
  if (moodRows == null ||
      sleepRows == null ||
      healthRows == null ||
      familyRows == null ||
      prayerRows == null) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data(
    WellbeingWeek.compute(
      moods: moodRows,
      sleeps: sleepRows,
      healths: healthRows,
      families: familyRows,
      prayers: prayerRows,
      today: today,
    ),
  );
});
