/// Feeds the analysis with what the app actually recorded.
///
/// Two sources, and nothing else: the widgets with their daily logs, and the
/// prayer marks. Both are already on the device, so the analysis works with
/// no connection and says nothing the user cannot check against their own
/// grid. The areas the user said they want to strengthen come from the
/// profile when it is loaded; without it the analysis simply reports what it
/// can measure.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../habits/application/habit_stats_providers.dart';
import '../../habits/domain/habit_kind.dart';
import '../../habits/domain/habit_schedule.dart';
import '../../habits/domain/local_day.dart';
import '../../onboarding/data/onboarding_answers_store.dart';
import '../../onboarding/domain/onboarding_answers.dart';
import '../../prayer/application/prayer_log_providers.dart';
import '../../prayer/domain/prayer_log_status.dart';
import '../../stats/application/weekly_stats_provider.dart';
import '../domain/area_insight.dart';

/// How far back the analysis looks. Two weeks: long enough for a habit to
/// show a shape, short enough that what it says is still about now.
const int insightWindowDays = 14;

/// What each widget and the prayers did over the window.
final areaObservationsProvider = Provider<List<AreaObservation>>((ref) {
  final habits = ref.watch(activeHabitsProvider).value ?? const [];
  final logs = ref.watch(allHabitLogsProvider).value ?? const [];
  final prayers = ref.watch(recentPrayerLogsProvider).value ?? const [];
  final today = ref.watch(statsTodayProvider);

  final countsByHabit = <String, Map<LocalDay, int>>{};
  for (final log in logs) {
    (countsByHabit[log.habitId] ??=
        <LocalDay, int>{})[LocalDay.fromUtcMidnight(log.date)] = log.count;
  }

  final observations = <AreaObservation>[];
  for (final habit in habits) {
    final area = areaOfKind(HabitKind.fromCode(habit.kind));
    if (area == null) continue;
    final schedule = HabitSchedule.fromJson(habit.frequency);
    // A widget with no fixed days is left out, the same choice the daily
    // analysis makes: counting it every day would invent misses on days the
    // user never planned it for.
    if (schedule.type == HabitScheduleType.timesPerWeek) continue;

    final createdOn = LocalDay.fromLocalDateTime(habit.createdAt.toLocal());
    final counts = countsByHabit[habit.id] ?? const <LocalDay, int>{};
    final days = <bool?>[];
    var everMet = false;
    for (var offset = insightWindowDays - 1; offset >= 0; offset--) {
      final day = today.addDays(-offset);
      final planned = !day.isBefore(createdOn) && schedule.isScheduledOn(day);
      if (!planned) {
        days.add(null);
        continue;
      }
      final done = (counts[day] ?? 0) >= habit.targetCount;
      if (done) everMet = true;
      days.add(done);
    }

    observations.add(
      AreaObservation(
        area: area,
        title: habit.title,
        habitId: habit.id,
        reminderMinutes: habit.reminderMinutes,
        dailyTarget: habit.targetCount,
        everMetTarget: everMet,
        days: days,
      ),
    );
  }

  final prayerDays = _prayerDays(prayers, today);
  if (prayerDays.any((day) => day != null)) {
    observations.add(
      AreaObservation(
        area: FocusArea.prayer,
        title: '',
        days: prayerDays,
      ),
    );
  }

  return observations;
});

/// The prayers, day by day: done when all five were marked as prayed.
///
/// A day with no marks at all is left out rather than counted as missed —
/// the app cannot tell "did not pray" from "did not open the app", and
/// saying the first when it means the second is the one mistake this screen
/// must never make. `qaza` is a prayer made up late, so it does not count
/// towards a day that was kept.
List<bool?> _prayerDays(List<PrayerLog> logs, LocalDay today) {
  final markedByDay = <LocalDay, int>{};
  final prayedByDay = <LocalDay, int>{};
  for (final log in logs) {
    final day = LocalDay.fromUtcMidnight(log.date);
    markedByDay[day] = (markedByDay[day] ?? 0) + 1;
    final status = PrayerLogStatus.fromCode(log.status);
    if (status == PrayerLogStatus.alone || status == PrayerLogStatus.jamaah) {
      prayedByDay[day] = (prayedByDay[day] ?? 0) + 1;
    }
  }

  return [
    for (var offset = insightWindowDays - 1; offset >= 0; offset--)
      () {
        final day = today.addDays(-offset);
        if ((markedByDay[day] ?? 0) == 0) return null;
        return (prayedByDay[day] ?? 0) >= dailyPrayerCount;
      }(),
  ];
}

/// The five daily prayers.
const int dailyPrayerCount = 5;

/// Which life area a widget belongs to. A widget whose kind belongs to no
/// area (a custom one) is left out of the analysis rather than filed under a
/// guess.
FocusArea? areaOfKind(HabitKind kind) {
  return switch (kind) {
    HabitKind.quran ||
    HabitKind.quranListen ||
    HabitKind.tafsir =>
      FocusArea.quran,
    HabitKind.zikr ||
    HabitKind.salawat ||
    HabitKind.istighfar ||
    HabitKind.dua ||
    HabitKind.tahajjud ||
    HabitKind.mosque ||
    HabitKind.fasting =>
      FocusArea.prayer,
    HabitKind.sport ||
    HabitKind.running ||
    HabitKind.walk ||
    HabitKind.cycling ||
    HabitKind.stretch ||
    HabitKind.sunlight ||
    HabitKind.water ||
    HabitKind.diet ||
    HabitKind.vitamins ||
    HabitKind.weightCheck =>
      FocusArea.health,
    HabitKind.family ||
    HabitKind.charity ||
    HabitKind.parents ||
    HabitKind.children ||
    HabitKind.guest =>
      FocusArea.family,
    HabitKind.study ||
    HabitKind.book ||
    HabitKind.language ||
    HabitKind.focus ||
    HabitKind.course ||
    HabitKind.memorize =>
      FocusArea.study,
    HabitKind.sleep || HabitKind.nap || HabitKind.earlyRise => FocusArea.sleep,
    HabitKind.mood ||
    HabitKind.journal ||
    HabitKind.gratitude ||
    HabitKind.breathing ||
    HabitKind.noPhone =>
      FocusArea.mood,
    HabitKind.custom => null,
  };
}

/// The sign-up answers as this device remembers them.
///
/// Read from the device and not from the account on purpose: an analysis
/// that works offline cannot wait on a network call for the user's own
/// answers. Null until the store has loaded.
///
/// Exposed here, in the analysis's own layer, so that anything built on top
/// of the analysis — the AI request in `features/ai`, for instance — reads
/// the answers through this rather than reaching into the onboarding
/// feature's `data/` layer.
final insightAnswersProvider = Provider<OnboardingAnswers?>((ref) {
  return ref.watch(savedOnboardingAnswersProvider).value;
});

/// The areas the user said they want to strengthen.
final wantedAreasProvider = Provider<List<FocusArea>>((ref) {
  return ref.watch(insightAnswersProvider)?.focusAreas.toList() ?? const [];
});

/// The analysis itself, weakest area first.
final areaInsightsProvider = Provider<List<AreaInsight>>((ref) {
  return AreaAnalysis.compute(
    observations: ref.watch(areaObservationsProvider),
    wanted: ref.watch(wantedAreasProvider),
  );
});
