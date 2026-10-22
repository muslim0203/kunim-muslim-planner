// The rules that turn the sign-up answers into a day.
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/habits/domain/habit_kind.dart';
import 'package:kunim/features/onboarding/domain/onboarding_answers.dart';
import 'package:kunim/features/onboarding/domain/suggestion_engine.dart';

List<HabitKind> kindsOf(List<WidgetSuggestion> plan) =>
    [for (final suggestion in plan) suggestion.kind];

WidgetSuggestion forKind(List<WidgetSuggestion> plan, HabitKind kind) =>
    plan.firstWhere((suggestion) => suggestion.kind == kind);

void main() {
  test('an empty form suggests nothing', () {
    expect(SuggestionEngine.suggest(const OnboardingAnswers()), isEmpty);
    // Even with a budget: the minutes say how much, never what.
    expect(
      SuggestionEngine.suggest(const OnboardingAnswers(dailyMinutes: 60)),
      isEmpty,
    );
  });

  test('an interest becomes a widget of its own kind', () {
    final plan = SuggestionEngine.suggest(
      const OnboardingAnswers(
        interests: {Interest.quran, Interest.sport},
        dailyMinutes: 60,
      ),
    );

    expect(kindsOf(plan), containsAll([HabitKind.quran, HabitKind.sport]));
    expect(forKind(plan, HabitKind.quran).reason, SuggestionReason.interest);
    expect(
      forKind(plan, HabitKind.sport).dailyTarget,
      HabitKind.sport.dailyTarget,
    );
  });

  test('a weak area outranks the same thing named as an interest', () {
    final plan = SuggestionEngine.suggest(
      const OnboardingAnswers(
        interests: {Interest.quran},
        focusAreas: {FocusArea.quran},
        dailyMinutes: 60,
      ),
    );

    // One widget, not two, and it is there because the user called it weak.
    expect(
        kindsOf(plan).where((kind) => kind == HabitKind.quran), hasLength(1));
    expect(forKind(plan, HabitKind.quran).reason, SuggestionReason.focusArea);
    expect(plan.first.kind, HabitKind.quran, reason: 'strongest comes first');
  });

  test('what the work implies fills a plan the user left thin', () {
    final plan = SuggestionEngine.suggest(
      const OnboardingAnswers(occupation: Occupation.office, dailyMinutes: 60),
    );

    // A desk day is short of movement, not of thinking time.
    expect(kindsOf(plan), containsAll([HabitKind.sport, HabitKind.water]));
    expect(forKind(plan, HabitKind.sport).reason, SuggestionReason.occupation);
  });

  test('what the user said outranks what the work implies', () {
    final plan = SuggestionEngine.suggest(
      const OnboardingAnswers(
        occupation: Occupation.office,
        interests: {Interest.book},
        dailyMinutes: 60,
      ),
    );

    expect(plan.first.kind, HabitKind.book);
    expect(plan.first.reason, SuggestionReason.interest);
  });

  test('a short day gets smaller targets, not a longer list', () {
    const answers = OnboardingAnswers(
      focusAreas: {FocusArea.study},
      interests: {Interest.sport, Interest.book},
      dailyMinutes: 15,
    );

    final plan = SuggestionEngine.suggest(answers);
    final minutes = plan.fold<int>(
      0,
      (total, suggestion) => total + suggestion.estimatedMinutes,
    );

    expect(minutes, lessThanOrEqualTo(15));
    expect(plan, isNotEmpty);
    // The strongest statement keeps its place even when it has to shrink.
    expect(plan.first.kind, HabitKind.study);
    expect(
      plan.first.dailyTarget,
      lessThan(HabitKind.study.dailyTarget),
      reason: 'a 20-minute default cannot fit a 15-minute day',
    );
  });

  test('a long day keeps every suggestion whole', () {
    final plan = SuggestionEngine.suggest(
      const OnboardingAnswers(
        interests: {Interest.book, Interest.sport},
        dailyMinutes: 90,
      ),
    );

    expect(
      forKind(plan, HabitKind.book).dailyTarget,
      HabitKind.book.dailyTarget,
    );
    expect(
      forKind(plan, HabitKind.sport).dailyTarget,
      HabitKind.sport.dailyTarget,
    );
  });

  test('water and an early night cost the day nothing', () {
    final plan = SuggestionEngine.suggest(
      const OnboardingAnswers(
        // A day with no minutes left at all.
        focusAreas: {FocusArea.study, FocusArea.sleep, FocusArea.health},
        dailyMinutes: 15,
      ),
    );

    expect(kindsOf(plan), contains(HabitKind.water));
    expect(kindsOf(plan), contains(HabitKind.sleep));
    expect(forKind(plan, HabitKind.water).estimatedMinutes, 0);
    expect(forKind(plan, HabitKind.sleep).estimatedMinutes, 0);
  });

  test('a home screen is never buried', () {
    final plan = SuggestionEngine.suggest(
      OnboardingAnswers(
        occupation: Occupation.student,
        interests: Interest.values.toSet(),
        focusAreas: FocusArea.values.toSet(),
        dailyMinutes: 600,
      ),
    );

    expect(plan.length, lessThanOrEqualTo(SuggestionEngine.maxSuggestions));
  });

  test('each widget gets the hour its task usually fits in', () {
    final plan = SuggestionEngine.suggest(
      const OnboardingAnswers(
        interests: {Interest.quran, Interest.book, Interest.water},
        dailyMinutes: 90,
      ),
    );

    expect(forKind(plan, HabitKind.quran).reminderMinutes, 6 * 60 + 30);
    expect(forKind(plan, HabitKind.book).reminderMinutes, 21 * 60);
    // Drinking water has no hour of its own; a reminder would be noise.
    expect(forKind(plan, HabitKind.water).reminderMinutes, isNull);
  });

  test('answers a newer app offered are carried, not acted on', () {
    final answers = OnboardingAnswers.fromSlugs(
      occupation: 'falconer',
      interests: const ['quran', 'falconry'],
      focusAreas: const ['health'],
      dailyMinutes: 45,
    );

    expect(answers.occupation, isNull, reason: 'unknown slug, no rule for it');
    expect(answers.interests, {Interest.quran});
    expect(answers.focusAreas, {FocusArea.health});
    expect(
        kindsOf(SuggestionEngine.suggest(answers)), contains(HabitKind.quran));
  });

  test('a budget outside what a day holds is pulled back inside', () {
    expect(const OnboardingAnswers().budget, DailyBudget.fallback);
    expect(const OnboardingAnswers(dailyMinutes: 0).budget, 5);
    expect(const OnboardingAnswers(dailyMinutes: 5000).budget, 600);
  });
}
