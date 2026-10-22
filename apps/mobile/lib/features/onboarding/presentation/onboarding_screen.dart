/// The questions asked once, when an account is created, and the day they
/// produce.
///
/// Four questions and a plan the user edits before anything is created:
/// nothing is written on their behalf until they keep it. Every question can
/// be skipped — an unanswered form simply suggests nothing, which is honest,
/// where a guessed plan would not be.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../habits/domain/habit_kind.dart';
import '../../habits/presentation/habit_kind_labels.dart';
import '../application/onboarding_controller.dart';
import '../domain/onboarding_answers.dart';
import '../domain/suggestion_engine.dart';
import 'onboarding_labels.dart';

/// Shows the questions. Opened right after an account is created, and
/// closed by finishing or skipping — either way the app goes on working.
Future<void> showOnboarding(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const OnboardingScreen(),
    ),
  );
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const int _questionCount = 4;

  int _step = 0;
  OnboardingAnswers _answers = const OnboardingAnswers();
  List<WidgetSuggestion> _plan = const [];

  /// The suggestions the user is keeping. Everything starts kept: the plan
  /// is a proposal to trim, not a list to assemble.
  final Set<HabitKind> _kept = {};
  bool _busy = false;

  bool get _onPlan => _step == _questionCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_onPlan ? l10n.onboardingPlanTitle : l10n.onboardingTitle),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.onboardingSkip),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: (_step + 1) / (_questionCount + 1),
              minHeight: 3,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(KunimSpacing.lg),
                child:
                    _onPlan ? _plannedDay(l10n, theme) : _question(l10n, theme),
              ),
            ),
            _Bar(
              busy: _busy,
              onBack: _step == 0 ? null : _back,
              label: _onPlan
                  ? (_plan.isEmpty
                      ? l10n.onboardingSkip
                      : l10n.onboardingPlanAccept)
                  : l10n.onboardingNext,
              onNext: _busy ? null : _next,
              backLabel: l10n.onboardingBack,
            ),
          ],
        ),
      ),
    );
  }

  // --- the questions --------------------------------------------------

  Widget _question(AppLocalizations l10n, ThemeData theme) {
    return switch (_step) {
      0 => _Step(
          title: l10n.onboardingStepOccupation,
          subtitle: l10n.onboardingSubtitle,
          child: Wrap(
            spacing: KunimSpacing.sm,
            runSpacing: KunimSpacing.sm,
            children: [
              for (final occupation in Occupation.values)
                ChoiceChip(
                  label: Text(occupationLabel(l10n, occupation)),
                  selected: _answers.occupation == occupation,
                  onSelected: (_) => setState(() {
                    _answers = OnboardingAnswers(
                      occupation:
                          _answers.occupation == occupation ? null : occupation,
                      interests: _answers.interests,
                      focusAreas: _answers.focusAreas,
                      dailyMinutes: _answers.dailyMinutes,
                    );
                  }),
                ),
            ],
          ),
        ),
      1 => _Step(
          title: l10n.onboardingStepInterests,
          child: Wrap(
            spacing: KunimSpacing.sm,
            runSpacing: KunimSpacing.sm,
            children: [
              for (final interest in Interest.values)
                FilterChip(
                  avatar: Icon(interestIcon(interest), size: 18),
                  label: Text(interestLabel(l10n, interest)),
                  selected: _answers.interests.contains(interest),
                  onSelected: (on) => setState(() {
                    final next = {..._answers.interests};
                    on ? next.add(interest) : next.remove(interest);
                    _answers = _answers.copyWith(interests: next);
                  }),
                ),
            ],
          ),
        ),
      2 => _Step(
          title: l10n.onboardingStepFocus,
          child: Wrap(
            spacing: KunimSpacing.sm,
            runSpacing: KunimSpacing.sm,
            children: [
              for (final area in FocusArea.values)
                FilterChip(
                  avatar: Icon(focusAreaIcon(area), size: 18),
                  label: Text(focusAreaLabel(l10n, area)),
                  selected: _answers.focusAreas.contains(area),
                  onSelected: (on) => setState(() {
                    final next = {..._answers.focusAreas};
                    on ? next.add(area) : next.remove(area);
                    _answers = _answers.copyWith(focusAreas: next);
                  }),
                ),
            ],
          ),
        ),
      _ => _Step(
          title: l10n.onboardingStepBudget,
          child: Wrap(
            spacing: KunimSpacing.sm,
            runSpacing: KunimSpacing.sm,
            children: [
              for (final minutes in DailyBudget.choices)
                ChoiceChip(
                  label: Text(l10n.onboardingMinutesChoice(minutes)),
                  selected: _answers.dailyMinutes == minutes,
                  onSelected: (_) => setState(() {
                    _answers = _answers.copyWith(dailyMinutes: minutes);
                  }),
                ),
            ],
          ),
        ),
    };
  }

  // --- the day that came out of them ----------------------------------

  Widget _plannedDay(AppLocalizations l10n, ThemeData theme) {
    if (_plan.isEmpty) {
      return _Step(
        title: l10n.onboardingPlanTitle,
        subtitle: l10n.onboardingPlanEmpty,
        child: const SizedBox.shrink(),
      );
    }

    final minutes = _plan
        .where((suggestion) => _kept.contains(suggestion.kind))
        .fold<int>(
            0, (total, suggestion) => total + suggestion.estimatedMinutes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.onboardingPlanBody, style: theme.textTheme.bodyMedium),
        const SizedBox(height: KunimSpacing.xs),
        Text(
          l10n.onboardingPlanLoad(minutes),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: KunimSpacing.md),
        for (final suggestion in _plan)
          CheckboxListTile(
            value: _kept.contains(suggestion.kind),
            onChanged: _busy
                ? null
                : (on) => setState(() {
                      (on ?? false)
                          ? _kept.add(suggestion.kind)
                          : _kept.remove(suggestion.kind);
                    }),
            secondary: CircleAvatar(
              backgroundColor: habitKindColor(suggestion.kind),
              child: Icon(
                habitKindIcon(suggestion.kind),
                color: Colors.white,
                size: 20,
              ),
            ),
            title: Text(habitKindName(l10n, suggestion.kind)),
            subtitle: Text(
              '${habitAmount(l10n, suggestion.kind, suggestion.dailyTarget)}'
              ' · ${reasonLabel(l10n, suggestion.reason)}',
            ),
          ),
      ],
    );
  }

  // --- moving through ---------------------------------------------------

  void _back() => setState(() => _step -= 1);

  Future<void> _next() async {
    if (!_onPlan) {
      setState(() {
        _step += 1;
        if (_onPlan) {
          _plan = SuggestionEngine.suggest(_answers);
          _kept
            ..clear()
            ..addAll(_plan.map((suggestion) => suggestion.kind));
        }
      });
      return;
    }
    await _apply();
  }

  Future<void> _apply() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final accepted = [
      for (final suggestion in _plan)
        if (_kept.contains(suggestion.kind))
          AcceptedSuggestion(
            suggestion: suggestion,
            title: habitKindName(l10n, suggestion.kind),
          ),
    ];
    if (accepted.isEmpty) {
      navigator.pop();
      return;
    }

    setState(() => _busy = true);
    try {
      final outcome = await ref
          .read(onboardingControllerProvider.notifier)
          .apply(answers: _answers, accepted: accepted);
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              outcome.answersSaved
                  ? l10n.onboardingDone
                  : l10n.onboardingAnswersNotSaved,
            ),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    }
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        if (subtitle case final text?) ...[
          const SizedBox(height: KunimSpacing.xs),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: KunimSpacing.lg),
        child,
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.busy,
    required this.onBack,
    required this.onNext,
    required this.label,
    required this.backLabel,
  });

  final bool busy;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String label;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(KunimSpacing.lg),
      child: Row(
        children: [
          if (onBack != null)
            TextButton(
              onPressed: busy ? null : onBack,
              child: Text(backLabel),
            ),
          const Spacer(),
          FilledButton(
            onPressed: onNext,
            child: busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(label),
          ),
        ],
      ),
    );
  }
}
