/// Asks for an analysis, and applies the parts of it the user accepts.
///
/// The rule the whole feature turns on: **the server never writes the user's
/// data.** It stores a proposal; this controller creates the widget on the
/// device through the ordinary habit write path, and the server learns of it
/// later through the ordinary sync, like any widget the user made by hand.
/// The `PATCH /ai/proposals/{id}` call records only what the user decided.
///
/// Because of that order, recording the decision is allowed to fail. The
/// widget already exists and is already in the outbox; losing the note that
/// the suggestion was taken is a missing statistic, not a lost write, and it
/// must never look to the user like the widget failed to save.
///
/// A plain [Notifier] rather than an `AsyncNotifier`: the resting state is
/// "nothing asked for yet", which is not a loading state, and an
/// `AsyncNotifier` would show a spinner for the frame before its `build`
/// resolved. The flags live in [AiAnalysisState] instead.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../habits/application/habit_mutation_controller.dart';
import '../../habits/domain/habit_schedule.dart';
import '../../insights/application/insight_providers.dart';
import '../data/ai_api.dart';
import '../domain/ai_analysis.dart';
import '../domain/analysis_facts.dart';

/// What the screen is showing.
class AiAnalysisState {
  const AiAnalysisState({
    this.proposal,
    this.accepted = const {},
    this.rejected = const {},
    this.isLoading = false,
    this.error,
  });

  /// Null until an analysis has come back.
  final AiProposal? proposal;

  /// Indices into `proposal.analysis.widgets` the user accepted. Kept by
  /// index rather than by object so a tapped row can grey out immediately.
  final Set<int> accepted;
  final Set<int> rejected;

  final bool isLoading;

  /// Why the last attempt produced nothing. The offline analysis below the
  /// card is unaffected either way.
  final AiErrorKind? error;

  bool get hasAnalysis => proposal != null;

  /// Whether every proposed widget has been decided on, so the list can
  /// collapse once there is nothing left to tap.
  bool get allDecided {
    final total = proposal?.analysis.widgets.length ?? 0;
    return total > 0 && accepted.length + rejected.length >= total;
  }

  AiAnalysisState withDecision({
    Set<int>? accepted,
    Set<int>? rejected,
  }) {
    return AiAnalysisState(
      proposal: proposal,
      accepted: accepted ?? this.accepted,
      rejected: rejected ?? this.rejected,
    );
  }
}

class AiAnalysisController extends Notifier<AiAnalysisState> {
  @override
  AiAnalysisState build() {
    // Nothing is asked for on its own. An analysis is a paid call and a
    // deliberate act: the user taps for it.
    return const AiAnalysisState();
  }

  /// Asks the analyst about what this device has recorded.
  ///
  /// [locale] is the language the app is showing right now, so the answer
  /// comes back in the language the user is reading.
  Future<void> analyse({required String locale}) async {
    if (state.isLoading) return;

    final facts = AnalysisFacts.from(
      insights: ref.read(areaInsightsProvider),
      observations: ref.read(areaObservationsProvider),
      windowDays: insightWindowDays,
      locale: locale,
      answers: ref.read(insightAnswersProvider),
    );

    // Answered here rather than by the server: a 422 costs nothing, but it
    // is still a round trip to be told what this device already knows.
    if (!facts.hasSomethingToAnalyse) {
      state = const AiAnalysisState(error: AiErrorKind.notEnoughData);
      return;
    }

    state = const AiAnalysisState(isLoading: true);
    try {
      final proposal = await ref.read(aiApiProvider).requestAnalysis(facts);
      state = AiAnalysisState(proposal: proposal);
    } on AiApiException catch (failure) {
      state = AiAnalysisState(error: failure.kind);
    }
  }

  /// Creates the proposed widget on this device, then tells the server the
  /// suggestion was taken.
  Future<void> acceptWidget(int index) async {
    final current = state;
    final widget = _undecided(current, index);
    if (widget == null) return;

    await ref.read(habitMutationControllerProvider.notifier).createHabit(
          title: widget.title,
          schedule: const HabitSchedule.everyDay(),
          targetCount: widget.dailyTarget,
          kind: widget.kind,
          reminderMinutes: widget.reminderMinutes,
        );

    // The widget exists from here on. Everything below is bookkeeping.
    final next = current.withDecision(accepted: {...current.accepted, index});
    state = next;
    await _record(next);
  }

  /// Dismisses one proposal. Nothing is written; the server is told so the
  /// next analysis is not judged on a suggestion nobody wanted.
  Future<void> rejectWidget(int index) async {
    final current = state;
    if (_undecided(current, index) == null) return;

    final next = current.withDecision(rejected: {...current.rejected, index});
    state = next;
    await _record(next);
  }

  /// Puts the screen back to its resting state, leaving any widget the user
  /// accepted exactly where it is.
  void clear() => state = const AiAnalysisState();

  /// The proposal at [index], or null if there is none or it was already
  /// decided. Both taps need the same check, and tapping twice must not
  /// create the same widget twice.
  AiWidgetProposal? _undecided(AiAnalysisState current, int index) {
    final widgets = current.proposal?.analysis.widgets;
    if (widgets == null || index < 0 || index >= widgets.length) return null;
    if (current.accepted.contains(index)) return null;
    if (current.rejected.contains(index)) return null;
    return widgets[index];
  }

  /// Tells the server what became of the proposal as a whole.
  ///
  /// The three statuses it stores are about the proposal, not about one
  /// widget, so the outcome is worked out from the tally: everything taken
  /// is `accepted`, some of it is `modified`, none of it is `rejected`.
  /// `applied_diff` carries which kinds were taken — enough to tell a useful
  /// suggestion from a popular one later, and not a word of the user's own
  /// text.
  Future<void> _record(AiAnalysisState current) async {
    final proposal = current.proposal;
    if (proposal == null) return;

    final widgets = proposal.analysis.widgets;
    final outcome = current.accepted.isEmpty
        ? AiProposalOutcome.rejected
        : current.accepted.length == widgets.length
            ? AiProposalOutcome.accepted
            : AiProposalOutcome.modified;

    try {
      await ref.read(aiApiProvider).record(
            proposal.id,
            outcome,
            appliedDiff: {
              'accepted_kinds': [
                for (final index in current.accepted) widgets[index].kind.code,
              ],
              'rejected_kinds': [
                for (final index in current.rejected) widgets[index].kind.code,
              ],
            },
          );
    } on AiApiException {
      // Deliberately swallowed: see the library comment. The user's widget is
      // already written, and a failed note must not look like a failed save.
    }
  }
}

final aiAnalysisControllerProvider =
    NotifierProvider<AiAnalysisController, AiAnalysisState>(
  AiAnalysisController.new,
);
