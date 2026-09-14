/// One goal: its description and deadline, a progress slider, and its
/// milestones, which can be added, renamed, ticked off or removed.
///
/// The progress number is the goal's own `progress_percent`, set by the user;
/// the milestone count is shown beside it, never in its place (see
/// `domain/goal_progress.dart`).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/db/app_database.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../application/goals_providers.dart';
import '../domain/goal_progress.dart';
import 'goal_editors.dart';

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final data = ref.watch(goalWithMilestonesProvider(goalId));

    Widget message(Widget child) => Scaffold(
          appBar: AppBar(title: Text(l10n.moduleGrowth)),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(KunimSpacing.lg),
              child: child,
            ),
          ),
        );

    if (data.hasError) return message(Text(l10n.errorGeneric));
    final value = data.value;
    if (value == null) return message(const CircularProgressIndicator());
    final goal = value.goal;
    if (goal == null || goal.deletedAt != null) {
      return message(Text(l10n.goalNotFound, textAlign: TextAlign.center));
    }

    final milestones = value.milestones;
    final summary =
        GoalProgressSummary.of(goal, milestones, now: DateTime.now());
    final done = milestones.where((m) => m.completedAt != null).length;
    final nextSortOrder = milestones.isEmpty
        ? 0
        : milestones.map((m) => m.sortOrder).reduce(math.max) + 1;
    final targetDate = goal.targetDate;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.moduleGrowth),
        actions: [
          IconButton(
            tooltip: l10n.goalEdit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showGoalEditor(
              context,
              goal: goal,
              onDeleted: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(KunimSpacing.lg),
        children: [
          HeritageCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(goal.title, style: theme.textTheme.headlineSmall),
                if (goal.description != null) ...[
                  const SizedBox(height: KunimSpacing.xs),
                  Text(
                    goal.description!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ],
                const SizedBox(height: KunimSpacing.md),
                Wrap(
                  spacing: KunimSpacing.md,
                  runSpacing: KunimSpacing.xs,
                  children: [
                    if (targetDate != null)
                      GoalMetaLabel(
                        icon: Icons.event_outlined,
                        text: formatGoalDate(context, targetDate),
                      ),
                    GoalMetaLabel(
                      icon: Icons.hourglass_empty_rounded,
                      text: goalDeadlineLabel(l10n, summary.daysRemaining),
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
          ),
          const SizedBox(height: KunimSpacing.lg),
          _ProgressCard(goal: goal),
          const SizedBox(height: KunimSpacing.xl),
          Text(l10n.goalMilestones, style: theme.textTheme.titleMedium),
          if (milestones.isNotEmpty)
            Text(
              l10n.goalMilestonesDoneCount(done, milestones.length),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          const SizedBox(height: KunimSpacing.sm),
          if (milestones.isEmpty)
            Text(
              l10n.goalMilestonesEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            )
          else
            for (final milestone in milestones)
              Padding(
                padding: const EdgeInsets.only(bottom: KunimSpacing.xs),
                child: _MilestoneRow(milestone: milestone),
              ),
          const SizedBox(height: KunimSpacing.md),
          OutlinedButton.icon(
            onPressed: () => showMilestoneEditor(
              context,
              goalId: goal.id,
              sortOrder: nextSortOrder,
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.goalAddMilestone),
          ),
        ],
      ),
    );
  }
}

/// The progress number and its slider. While dragging, the number follows
/// the thumb; the value is written once, when the drag ends.
class _ProgressCard extends ConsumerStatefulWidget {
  const _ProgressCard({required this.goal});

  final Goal goal;

  @override
  ConsumerState<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends ConsumerState<_ProgressCard> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value =
        (_dragging ?? widget.goal.progressPercent.toDouble()).clamp(0.0, 100.0);
    final percent = value.round();

    return HeritageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.goalProgressLabel,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                l10n.goalProgressValue(percent),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: KunimModuleColors.mood,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            max: 100,
            divisions: 20,
            label: l10n.goalProgressValue(percent),
            activeColor: KunimModuleColors.mood,
            onChanged: (next) => setState(() => _dragging = next),
            onChangeEnd: (next) async {
              await ref.read(goalsControllerProvider.notifier).updateProgress(
                    id: widget.goal.id,
                    progressPercent: next.round(),
                  );
              if (mounted) setState(() => _dragging = null);
            },
          ),
        ],
      ),
    );
  }
}

class _MilestoneRow extends ConsumerWidget {
  const _MilestoneRow({required this.milestone});

  final Milestone milestone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final completed = milestone.completedAt != null;
    final controller = ref.read(goalsControllerProvider.notifier);

    return HeritageCard(
      onTap: () => showMilestoneEditor(
        context,
        goalId: milestone.goalId,
        milestone: milestone,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: KunimSpacing.sm,
        vertical: KunimSpacing.xs,
      ),
      child: Row(
        children: [
          Checkbox(
            value: completed,
            onChanged: (checked) => checked == true
                ? controller.completeMilestone(milestone.id)
                : controller.reopenMilestone(milestone.id),
          ),
          const SizedBox(width: KunimSpacing.xs),
          Expanded(
            child: Text(
              milestone.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration: completed ? TextDecoration.lineThrough : null,
                color: completed ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
