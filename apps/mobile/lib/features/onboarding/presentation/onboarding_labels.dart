/// Names and icons for the sign-up questions.
///
/// An interest and a focus area are shown with the name of the thing they
/// become — the widget's own name, the life area's own name — so the user
/// recognises on the home screen what they chose here.
library;

import 'package:flutter/material.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../habits/presentation/habit_kind_labels.dart';
import '../domain/onboarding_answers.dart';
import '../domain/suggestion_engine.dart';

String occupationLabel(AppLocalizations l10n, Occupation occupation) {
  return switch (occupation) {
    Occupation.student => l10n.onboardingWorkStudent,
    Occupation.teacher => l10n.onboardingWorkTeacher,
    Occupation.office => l10n.onboardingWorkOffice,
    Occupation.business => l10n.onboardingWorkBusiness,
    Occupation.medical => l10n.onboardingWorkMedical,
    Occupation.it => l10n.onboardingWorkIt,
    Occupation.labour => l10n.onboardingWorkLabour,
    Occupation.driver => l10n.onboardingWorkDriver,
    Occupation.homemaker => l10n.onboardingWorkHomemaker,
    Occupation.religious => l10n.onboardingWorkReligious,
    Occupation.other => l10n.onboardingWorkOther,
  };
}

String interestLabel(AppLocalizations l10n, Interest interest) =>
    habitKindName(l10n, SuggestionEngine.kindOfInterest(interest));

IconData interestIcon(Interest interest) =>
    habitKindIcon(SuggestionEngine.kindOfInterest(interest));

/// The life areas, under the names the rest of the app uses for them.
String focusAreaLabel(AppLocalizations l10n, FocusArea area) {
  return switch (area) {
    FocusArea.prayer => l10n.modulePrayer,
    FocusArea.quran => l10n.moduleQuran,
    FocusArea.health => l10n.moduleHealth,
    FocusArea.family => l10n.moduleFamily,
    FocusArea.work => l10n.moduleWork,
    FocusArea.study => l10n.habitKindStudy,
    FocusArea.sleep => l10n.moduleSleep,
    FocusArea.mood => l10n.moduleMood,
  };
}

IconData focusAreaIcon(FocusArea area) {
  return switch (area) {
    FocusArea.prayer => Icons.mosque_outlined,
    FocusArea.quran => Icons.auto_stories_rounded,
    FocusArea.health => Icons.fitness_center_rounded,
    FocusArea.family => Icons.favorite_outline_rounded,
    FocusArea.work => Icons.work_outline_rounded,
    FocusArea.study => Icons.school_outlined,
    FocusArea.sleep => Icons.dark_mode_outlined,
    FocusArea.mood => Icons.self_improvement_rounded,
  };
}

/// One line saying why a widget is being suggested. A suggestion nobody can
/// explain is one nobody keeps.
String reasonLabel(AppLocalizations l10n, SuggestionReason reason) {
  return switch (reason) {
    SuggestionReason.focusArea => l10n.onboardingReasonFocus,
    SuggestionReason.interest => l10n.onboardingReasonInterest,
    SuggestionReason.occupation => l10n.onboardingReasonOccupation,
  };
}
