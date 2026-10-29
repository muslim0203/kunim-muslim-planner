/// Names, icons, colours, units and module links for the widget kinds
/// (`HabitKind`).
///
/// The home grid is built from these: a widget looks like the life area it
/// belongs to, and opens that area's screen when it has one.
library;

import 'package:flutter/material.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/tokens.dart';
import '../domain/habit_kind.dart';

String habitKindName(AppLocalizations l10n, HabitKind kind) {
  return switch (kind) {
    HabitKind.custom => l10n.habitKindCustom,
    HabitKind.book => l10n.habitKindBook,
    HabitKind.quran => l10n.habitKindQuran,
    HabitKind.study => l10n.habitKindStudy,
    HabitKind.quranListen => l10n.habitKindQuranListen,
    HabitKind.tafsir => l10n.habitKindTafsir,
    HabitKind.zikr => l10n.habitKindZikr,
    HabitKind.salawat => l10n.habitKindSalawat,
    HabitKind.istighfar => l10n.habitKindIstighfar,
    HabitKind.tahajjud => l10n.habitKindTahajjud,
    HabitKind.mosque => l10n.habitKindMosque,
    HabitKind.dua => l10n.habitKindDua,
    HabitKind.fasting => l10n.habitKindFasting,
    HabitKind.charity => l10n.habitKindCharity,
    HabitKind.sport => l10n.habitKindSport,
    HabitKind.running => l10n.habitKindRunning,
    HabitKind.walk => l10n.habitKindWalk,
    HabitKind.cycling => l10n.habitKindCycling,
    HabitKind.stretch => l10n.habitKindStretch,
    HabitKind.sunlight => l10n.habitKindSunlight,
    HabitKind.vitamins => l10n.habitKindVitamins,
    HabitKind.weightCheck => l10n.habitKindWeightCheck,
    HabitKind.water => l10n.habitKindWater,
    HabitKind.diet => l10n.habitKindDiet,
    HabitKind.language => l10n.habitKindLanguage,
    HabitKind.focus => l10n.habitKindFocus,
    HabitKind.course => l10n.habitKindCourse,
    HabitKind.memorize => l10n.habitKindMemorize,
    HabitKind.family => l10n.habitKindFamily,
    HabitKind.parents => l10n.habitKindParents,
    HabitKind.children => l10n.habitKindChildren,
    HabitKind.guest => l10n.habitKindGuest,
    HabitKind.mood => l10n.habitKindMood,
    HabitKind.journal => l10n.habitKindJournal,
    HabitKind.gratitude => l10n.habitKindGratitude,
    HabitKind.breathing => l10n.habitKindBreathing,
    HabitKind.noPhone => l10n.habitKindNoPhone,
    HabitKind.sleep => l10n.habitKindSleep,
    HabitKind.nap => l10n.habitKindNap,
    HabitKind.earlyRise => l10n.habitKindEarlyRise,
  };
}

IconData habitKindIcon(HabitKind kind) {
  return switch (kind) {
    HabitKind.custom => Icons.check_circle_outline_rounded,
    HabitKind.book => Icons.menu_book_rounded,
    HabitKind.quran => Icons.auto_stories_rounded,
    HabitKind.study => Icons.school_outlined,
    HabitKind.quranListen => Icons.headphones_rounded,
    HabitKind.tafsir => Icons.import_contacts_rounded,
    HabitKind.zikr => Icons.spa_outlined,
    HabitKind.salawat => Icons.auto_awesome_rounded,
    HabitKind.istighfar => Icons.wb_twilight,
    HabitKind.tahajjud => Icons.bedtime_rounded,
    HabitKind.mosque => Icons.mosque_rounded,
    HabitKind.dua => Icons.front_hand_outlined,
    HabitKind.fasting => Icons.brightness_3_rounded,
    HabitKind.charity => Icons.volunteer_activism_outlined,
    HabitKind.sport => Icons.fitness_center_rounded,
    HabitKind.running => Icons.directions_run_rounded,
    HabitKind.walk => Icons.directions_walk_rounded,
    HabitKind.cycling => Icons.directions_bike_rounded,
    HabitKind.stretch => Icons.accessibility_new_rounded,
    HabitKind.sunlight => Icons.wb_sunny_rounded,
    HabitKind.vitamins => Icons.medication_rounded,
    HabitKind.weightCheck => Icons.monitor_weight_rounded,
    HabitKind.water => Icons.local_drink_outlined,
    HabitKind.diet => Icons.restaurant_menu_rounded,
    HabitKind.language => Icons.translate_rounded,
    HabitKind.focus => Icons.center_focus_strong_rounded,
    HabitKind.course => Icons.play_lesson_rounded,
    HabitKind.memorize => Icons.psychology_rounded,
    HabitKind.family => Icons.favorite_outline_rounded,
    HabitKind.parents => Icons.elderly_rounded,
    HabitKind.children => Icons.child_care_rounded,
    HabitKind.guest => Icons.groups_rounded,
    HabitKind.mood => Icons.self_improvement_rounded,
    HabitKind.journal => Icons.edit_note_rounded,
    HabitKind.gratitude => Icons.emoji_emotions_rounded,
    HabitKind.breathing => Icons.air_rounded,
    HabitKind.noPhone => Icons.phone_disabled_rounded,
    HabitKind.sleep => Icons.dark_mode_outlined,
    HabitKind.nap => Icons.airline_seat_individual_suite_rounded,
    HabitKind.earlyRise => Icons.alarm_rounded,
  };
}

/// The life area's colour, so a widget carries the same one as the section
/// it belongs to.
Color habitKindColor(HabitKind kind) {
  return switch (kind) {
    HabitKind.quran ||
    HabitKind.book ||
    HabitKind.quranListen ||
    HabitKind.tafsir =>
      KunimModuleColors.quran,
    HabitKind.zikr ||
    HabitKind.mood ||
    HabitKind.journal ||
    HabitKind.gratitude ||
    HabitKind.breathing ||
    HabitKind.noPhone =>
      KunimModuleColors.mood,
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
      KunimModuleColors.health,
    HabitKind.family ||
    HabitKind.charity ||
    HabitKind.parents ||
    HabitKind.children ||
    HabitKind.guest =>
      KunimModuleColors.family,
    HabitKind.sleep ||
    HabitKind.nap ||
    HabitKind.earlyRise =>
      KunimModuleColors.sleep,
    HabitKind.study ||
    HabitKind.language ||
    HabitKind.focus ||
    HabitKind.course ||
    HabitKind.memorize =>
      KunimModuleColors.work,
    HabitKind.custom ||
    HabitKind.dua ||
    HabitKind.fasting ||
    HabitKind.salawat ||
    HabitKind.istighfar ||
    HabitKind.tahajjud ||
    HabitKind.mosque =>
      KunimModuleColors.prayer,
  };
}

/// The screen this kind of widget belongs to, or null when the widget is
/// the whole feature (a book, zikr, a custom one) — those open their own
/// editor instead.
String? habitKindRoute(HabitKind kind) {
  return switch (kind) {
    HabitKind.mood ||
    HabitKind.journal ||
    HabitKind.gratitude ||
    HabitKind.breathing ||
    HabitKind.noPhone =>
      KunimRoutes.mood,
    HabitKind.family ||
    HabitKind.charity ||
    HabitKind.parents ||
    HabitKind.children ||
    HabitKind.guest =>
      KunimRoutes.family,
    HabitKind.sleep ||
    HabitKind.nap ||
    HabitKind.earlyRise =>
      KunimRoutes.sleep,
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
      KunimRoutes.health,
    HabitKind.study ||
    HabitKind.language ||
    HabitKind.focus ||
    HabitKind.course ||
    HabitKind.memorize =>
      KunimRoutes.goals,
    HabitKind.custom ||
    HabitKind.book ||
    HabitKind.quran ||
    HabitKind.quranListen ||
    HabitKind.tafsir ||
    HabitKind.zikr ||
    HabitKind.salawat ||
    HabitKind.istighfar ||
    HabitKind.dua ||
    HabitKind.tahajjud ||
    HabitKind.mosque ||
    HabitKind.fasting =>
      null,
  };
}

/// "10 bet", "5 oyat", "30 daqiqa" — the amount in the widget's own unit.
String habitAmount(AppLocalizations l10n, HabitKind kind, int count) {
  return switch (kind) {
    HabitKind.book || HabitKind.tafsir => l10n.habitUnitPages(count),
    HabitKind.quran => l10n.habitUnitAyahs(count),
    HabitKind.study ||
    HabitKind.sport ||
    HabitKind.running ||
    HabitKind.walk ||
    HabitKind.cycling ||
    HabitKind.stretch ||
    HabitKind.sunlight ||
    HabitKind.language ||
    HabitKind.focus ||
    HabitKind.course ||
    HabitKind.memorize ||
    HabitKind.quranListen ||
    HabitKind.breathing ||
    HabitKind.noPhone ||
    HabitKind.children ||
    HabitKind.family =>
      l10n.habitUnitMinutes(count),
    HabitKind.water => l10n.habitUnitGlasses(count),
    HabitKind.custom ||
    HabitKind.zikr ||
    HabitKind.salawat ||
    HabitKind.istighfar ||
    HabitKind.dua ||
    HabitKind.tahajjud ||
    HabitKind.mosque ||
    HabitKind.fasting ||
    HabitKind.charity ||
    HabitKind.diet ||
    HabitKind.vitamins ||
    HabitKind.weightCheck ||
    HabitKind.mood ||
    HabitKind.journal ||
    HabitKind.gratitude ||
    HabitKind.parents ||
    HabitKind.guest ||
    HabitKind.sleep ||
    HabitKind.nap ||
    HabitKind.earlyRise =>
      l10n.habitUnitTimes(count),
  };
}
