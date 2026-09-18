/// Names, icons and units for the widget kinds (`HabitKind`).
library;

import 'package:flutter/material.dart';

import '../../../app/l10n/gen/app_localizations.dart';
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
  };
}

/// "10 bet", "5 oyat", "30 daqiqa" — the amount in the widget's own unit.
String habitAmount(AppLocalizations l10n, HabitKind kind, int count) {
  return switch (kind) {
    HabitKind.book => l10n.habitUnitPages(count),
    HabitKind.quran => l10n.habitUnitAyahs(count),
    HabitKind.study || HabitKind.sport => l10n.habitUnitMinutes(count),
    HabitKind.water => l10n.habitUnitGlasses(count),
    HabitKind.custom || HabitKind.zikr => l10n.habitUnitTimes(count),
  };
}
