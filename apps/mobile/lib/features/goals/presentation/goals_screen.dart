/// "Shaxsiy rivojlanish": the user's goals, closest deadline first. Opening
/// a goal shows its progress and milestones (`goal_detail_screen.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/db/app_database.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../application/goals_providers.dart';
import '../domain/goal_progress.dart';
import 'goal_editors.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final goals = ref.watch(activeGoalsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.moduleGrowth)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showGoalEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.goalNew),
      ),
      body: ListView(
        // Bottom room so the last card is never hidden under the button.
        padding: const EdgeInsets.fromLTRB(
          KunimSpacing.lg,
          KunimSpacing.lg,
          KunimSpacing.lg,
          96,
        ),
        children: [
          Text(
            l10n.goalIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: KunimSpacing.lg),
          Text(l10n.goalScreenTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: KunimSpacing.sm),
          ...switch (goals) {
            AsyncData(:final value) when value.isEmpty => [
                HeritageCard(
                  child: Text(
                    l10n.goalEmptyState,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            AsyncData(:final value) => [
                for (final goal in value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: KunimSpacing.sm),
                    child: _GoalCard(goal: goal),
                  ),
              ],
            AsyncError() => [Text(l10n.errorGeneric)],
            _ => [const Center(child: CircularProgressIndicator())],
          },
        ],
      ),
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final milestones =
        ref.watch(milestonesForGoalProvider(goal.id)).value ?? const [];
    final summary =
        GoalProgressSummary.of(goal, milestones, now: DateTime.now());
    final done = milestones.where((m) => m.completedAt != null).length;

    return HeritageCard(
      onTap: () => context.go(KunimRoutes.goal(goal.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(goal.title, style: theme.textTheme.titleSmall),
              ),
              const SizedBox(width: KunimSpacing.sm),
              Text(
                l10n.goalProgressValue(summary.displayProgressPercent),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: KunimModuleColors.mood,
                ),
              ),
            ],
          ),
          const SizedBox(height: KunimSpacing.sm),
          GoalProgressBar(percent: summary.displayProgressPercent),
          const SizedBox(height: KunimSpacing.sm),
          Wrap(
            spacing: KunimSpacing.md,
            runSpacing: KunimSpacing.xs,
            children: [
              GoalMetaLabel(
                icon: Icons.event_outlined,
                text: goalDeadlineLabel(l10n, summary.daysRemaining),
              ),
              if (milestones.isNotEmpty)
                GoalMetaLabel(
                  icon: Icons.flag_outlined,
                  text: l10n.goalMilestonesDoneCount(done, milestones.length),
                ),
              if (summary.isAtRisk)
                GoalMetaLabel(
                  icon: Icons.warning_amber_rounded,
                  text: l10n.goalAtRisk,
                  color: theme.colorScheme.error,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
