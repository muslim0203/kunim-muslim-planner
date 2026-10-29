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
    HabitKind.zikr => l10n.habitKindZikr,
    HabitKind.dua => l10n.habitKindDua,
    HabitKind.fasting => l10n.habitKindFasting,
    HabitKind.charity => l10n.habitKindCharity,
    HabitKind.sport => l10n.habitKindSport,
    HabitKind.running => l10n.habitKindRunning,
    HabitKind.walk => l10n.habitKindWalk,
    HabitKind.water => l10n.habitKindWater,
    HabitKind.diet => l10n.habitKindDiet,
    HabitKind.language => l10n.habitKindLanguage,
    HabitKind.family => l10n.habitKindFamily,
    HabitKind.mood => l10n.habitKindMood,
    HabitKind.journal => l10n.habitKindJournal,
    HabitKind.sleep => l10n.habitKindSleep,
    HabitKind.earlyRise => l10n.habitKindEarlyRise,
  };
}

IconData habitKindIcon(HabitKind kind) {
  return switch (kind) {
    HabitKind.custom => Icons.check_circle_outline_rounded,
    HabitKind.book => Icons.menu_book_rounded,
    HabitKind.quran => Icons.auto_stories_rounded,
    HabitKind.study => Icons.school_outlined,
    HabitKind.zikr => Icons.spa_outlined,
    HabitKind.dua => Icons.front_hand_outlined,
    HabitKind.fasting => Icons.brightness_3_rounded,
    HabitKind.charity => Icons.volunteer_activism_outlined,
    HabitKind.sport => Icons.fitness_center_rounded,
    HabitKind.running => Icons.directions_run_rounded,
    HabitKind.walk => Icons.directions_walk_rounded,
    HabitKind.water => Icons.local_drink_outlined,
    HabitKind.diet => Icons.restaurant_menu_rounded,
    HabitKind.language => Icons.translate_rounded,
    HabitKind.family => Icons.favorite_outline_rounded,
    HabitKind.mood => Icons.self_improvement_rounded,
    HabitKind.journal => Icons.edit_note_rounded,
    HabitKind.sleep => Icons.dark_mode_outlined,
    HabitKind.earlyRise => Icons.alarm_rounded,
  };
}

/// The life area's colour, so a widget carries the same one as the section
/// it belongs to.
Color habitKindColor(HabitKind kind) {
  return switch (kind) {
    HabitKind.quran || HabitKind.book => KunimModuleColors.quran,
    HabitKind.zikr ||
    HabitKind.mood ||
    HabitKind.journal =>
      KunimModuleColors.mood,
    HabitKind.sport ||
    HabitKind.running ||
    HabitKind.walk ||
    HabitKind.water ||
    HabitKind.diet =>
      KunimModuleColors.health,
    HabitKind.family || HabitKind.charity => KunimModuleColors.family,
    HabitKind.sleep || HabitKind.earlyRise => KunimModuleColors.sleep,
    HabitKind.study || HabitKind.language => KunimModuleColors.work,
    HabitKind.custom ||
    HabitKind.dua ||
    HabitKind.fasting =>
      KunimModuleColors.prayer,
  };
}

/// The screen this kind of widget belongs to, or null when the widget is
/// the whole feature (a book, zikr, a custom one) — those open their own
/// editor instead.
String? habitKindRoute(HabitKind kind) {
  return switch (kind) {
    HabitKind.mood || HabitKind.journal => KunimRoutes.mood,
    HabitKind.family || HabitKind.charity => KunimRoutes.family,
    HabitKind.sleep || HabitKind.earlyRise => KunimRoutes.sleep,
    HabitKind.sport ||
    HabitKind.running ||
    HabitKind.walk ||
    HabitKind.water ||
    HabitKind.diet =>
      KunimRoutes.health,
    HabitKind.study || HabitKind.language => KunimRoutes.goals,
    HabitKind.custom ||
    HabitKind.book ||
    HabitKind.quran ||
    HabitKind.zikr ||
    HabitKind.dua ||
    HabitKind.fasting =>
      null,
  };
}

/// "10 bet", "5 oyat", "30 daqiqa" — the amount in the widget's own unit.
String habitAmount(AppLocalizations l10n, HabitKind kind, int count) {
  return switch (kind) {
    HabitKind.book => l10n.habitUnitPages(count),
    HabitKind.quran => l10n.habitUnitAyahs(count),
    HabitKind.study ||
    HabitKind.sport ||
    HabitKind.running ||
    HabitKind.walk ||
    HabitKind.language ||
    HabitKind.family =>
      l10n.habitUnitMinutes(count),
    HabitKind.water => l10n.habitUnitGlasses(count),
    HabitKind.custom ||
    HabitKind.zikr ||
    HabitKind.dua ||
    HabitKind.fasting ||
    HabitKind.charity ||
    HabitKind.diet ||
    HabitKind.mood ||
    HabitKind.journal ||
    HabitKind.sleep ||
    HabitKind.earlyRise =>
      l10n.habitUnitTimes(count),
  };
}
