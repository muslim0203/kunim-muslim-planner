/// Applies what the sign-up questions produced.
///
/// Two separate things happen here, and they are deliberately not one
/// transaction:
///
/// - **The widgets are created on the device**, through the ordinary habit
///   write path, so they exist whether or not the network does. The app's
///   rule holds: nothing is written on the user's behalf until they say yes
///   — the suggestions screen is where they say it.
/// - **The answers are sent to the account**, so a second device starts from
///   the same picture. That call can fail, and when it does the plan still
///   stands; the screen says so rather than pretending the answers were
///   saved.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../habits/application/habit_mutation_controller.dart';
import '../../habits/domain/habit_schedule.dart';
import '../../profile/data/profile_api.dart';
import '../data/onboarding_answers_store.dart';
import '../domain/onboarding_answers.dart';
import '../domain/suggestion_engine.dart';

/// A suggestion the user kept, with the name it will carry on the home
/// screen. The name comes from the UI because it is a translated label, and
/// nothing below the presentation layer should hold one.
class AcceptedSuggestion {
  const AcceptedSuggestion({required this.suggestion, required this.title});

  final WidgetSuggestion suggestion;
  final String title;
}

/// What came of applying the answers.
class OnboardingOutcome {
  const OnboardingOutcome({
    required this.widgetsCreated,
    required this.answersSaved,
  });

  final int widgetsCreated;

  /// False when the answers could not be sent to the account — the widgets
  /// are still there.
  final bool answersSaved;
}

class OnboardingController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Idle until the questions are answered.
  }

  Future<OnboardingOutcome> apply({
    required OnboardingAnswers answers,
    required List<AcceptedSuggestion> accepted,
  }) async {
    state = const AsyncLoading();
    try {
      final habits = ref.read(habitMutationControllerProvider.notifier);
      for (final choice in accepted) {
        await habits.createHabit(
          title: choice.title,
          schedule: const HabitSchedule.everyDay(),
          targetCount: choice.suggestion.dailyTarget,
          kind: choice.suggestion.kind,
          reminderMinutes: choice.suggestion.reminderMinutes,
        );
      }

      // The device's copy first: it cannot fail, and it is the one the
      // analysis reads.
      await ref.read(onboardingAnswersStoreProvider).save(answers);
      final answersSaved = await _saveAnswers(answers);
      state = const AsyncData(null);
      return OnboardingOutcome(
        widgetsCreated: accepted.length,
        answersSaved: answersSaved,
      );
    } catch (error, stack) {
      state = AsyncError(error, stack);
      rethrow;
    }
  }

  /// Sends the answers to the account. Returns false on a failure the user
  /// can do nothing about right now; the questions can be answered again
  /// from the profile later.
  Future<bool> _saveAnswers(OnboardingAnswers answers) async {
    try {
      await ref.read(profileApiProvider).update(
            occupation: answers.occupation?.slug,
            interests: [
              for (final interest in answers.interests) interest.slug,
            ],
            focusAreas: [for (final area in answers.focusAreas) area.slug],
            dailyMinutes: answers.budget,
          );
      return true;
    } on ProfileApiException {
      return false;
    }
  }
}

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, void>(
  OnboardingController.new,
);
