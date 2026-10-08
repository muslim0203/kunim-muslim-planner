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
    HabitKind.sport => l10n.habitKindSport,
    HabitKind.water => l10n.habitKindWater,
    HabitKind.family => l10n.habitKindFamily,
    HabitKind.mood => l10n.habitKindMood,
    HabitKind.sleep => l10n.habitKindSleep,
  };
}

IconData habitKindIcon(HabitKind kind) {
  return switch (kind) {
    HabitKind.custom => Icons.check_circle_outline_rounded,
    HabitKind.book => Icons.menu_book_rounded,
    HabitKind.quran => Icons.auto_stories_rounded,
    HabitKind.study => Icons.school_outlined,
    HabitKind.zikr => Icons.spa_outlined,
    HabitKind.sport => Icons.fitness_center_rounded,
    HabitKind.water => Icons.local_drink_outlined,
    HabitKind.family => Icons.favorite_outline_rounded,
    HabitKind.mood => Icons.self_improvement_rounded,
    HabitKind.sleep => Icons.dark_mode_outlined,
  };
}

/// The life area's colour, so a widget carries the same one as the section
/// it belongs to.
Color habitKindColor(HabitKind kind) {
  return switch (kind) {
    HabitKind.quran || HabitKind.book => KunimModuleColors.quran,
    HabitKind.zikr || HabitKind.mood => KunimModuleColors.mood,
    HabitKind.sport || HabitKind.water => KunimModuleColors.health,
    HabitKind.family => KunimModuleColors.family,
    HabitKind.sleep => KunimModuleColors.sleep,
    HabitKind.study => KunimModuleColors.work,
    HabitKind.custom => KunimModuleColors.prayer,
  };
}

/// The screen this kind of widget belongs to, or null when the widget is
/// the whole feature (a book, zikr, a custom one) — those open their own
/// editor instead.
String? habitKindRoute(HabitKind kind) {
  return switch (kind) {
    HabitKind.mood => KunimRoutes.mood,
    HabitKind.family => KunimRoutes.family,
    HabitKind.sleep => KunimRoutes.sleep,
    HabitKind.sport || HabitKind.water => KunimRoutes.health,
    HabitKind.study => KunimRoutes.goals,
    HabitKind.quran => KunimRoutes.quran,
    HabitKind.custom || HabitKind.book || HabitKind.zikr => null,
  };
}

/// "10 bet", "5 oyat", "30 daqiqa" — the amount in the widget's own unit.
String habitAmount(AppLocalizations l10n, HabitKind kind, int count) {
  return switch (kind) {
    HabitKind.book => l10n.habitUnitPages(count),
    HabitKind.quran => l10n.habitUnitAyahs(count),
    HabitKind.study ||
    HabitKind.sport ||
    HabitKind.family =>
      l10n.habitUnitMinutes(count),
    HabitKind.water => l10n.habitUnitGlasses(count),
    HabitKind.custom ||
    HabitKind.zikr ||
    HabitKind.mood ||
    HabitKind.sleep =>
      l10n.habitUnitTimes(count),
  };
}
