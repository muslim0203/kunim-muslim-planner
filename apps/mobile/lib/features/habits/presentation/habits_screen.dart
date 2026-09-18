/// "Odatlar": every active habit with its cadence, streak and today's
/// check-in. New habits are added here; tapping one edits it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../application/habit_streak_provider.dart';
import '../application/habit_totals_provider.dart';
import '../application/habits_today_provider.dart';
import '../domain/habit_kind.dart';
import '../domain/habit_progress.dart';
import 'habit_editor.dart';
import 'habit_kind_labels.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final habits = ref.watch(allHabitsWithTodayProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.habitScreenTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showHabitEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.habitNew),
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
            l10n.habitIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: KunimSpacing.lg),
          ...switch (habits) {
            AsyncData(:final value) when value.isEmpty => [
                HeritageCard(
                  child: Text(
                    l10n.habitEmptyState,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            AsyncData(:final value) => [
                for (final habit in value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: KunimSpacing.sm),
                    child: _HabitRow(habit: habit),
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

class _HabitRow extends ConsumerWidget {
  const _HabitRow({required this.habit});

  final HabitToday habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final streak = ref.watch(habitStreakProvider(habit.habit.id)).value;
    final kind = HabitKind.fromCode(habit.habit.kind);
    final total = habit.habit.totalTarget;
    final progress = total == null
        ? null
        : HabitProgress(
            done: ref.watch(habitTotalsProvider)[habit.habit.id] ?? 0,
            total: total,
            perDay: habit.habit.targetCount,
          );
    final scheduledToday = habit.schedule.isScheduledOn(habit.day);
    final target = habit.habit.targetCount;

    return HeritageCard(
      onTap: () => showHabitEditor(context, habit: habit.habit),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(habit.habit.title, style: theme.textTheme.titleSmall),
                const SizedBox(height: KunimSpacing.xs),
                Text(
                  habitScheduleLabel(l10n, habit.schedule),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                if (progress != null) ...[
                  const SizedBox(height: KunimSpacing.xs),
                  Text(
                    '${progress.done} / '
                    '${habitAmount(l10n, kind, progress.total!)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: KunimSpacing.xs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(KunimRadii.small),
                    child: LinearProgressIndicator(
                      value: progress.ratio,
                      minHeight: 6,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: KunimSpacing.xs),
                  Text(
                    progress.isFinished
                        ? l10n.habitFinished
                        : l10n.habitFinishInDays(progress.daysLeft ?? 0),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                if (streak != null && streak.current > 0)
                  Text(
                    habitStreakLabel(l10n, streak),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                if (!scheduledToday)
                  Text(
                    l10n.habitNotScheduledToday,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
          if (scheduledToday) ...[
            const SizedBox(width: KunimSpacing.sm),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip:
                      habit.isDone ? l10n.habitUndoToday : l10n.habitLogToday,
                  isSelected: habit.isDone,
                  onPressed: () => toggleHabitToday(ref, habit),
                  icon: const Icon(Icons.radio_button_unchecked_rounded),
                  selectedIcon: const Icon(Icons.check_circle_rounded),
                  color: theme.colorScheme.primary,
                  iconSize: 32,
                ),
                if (target > 1)
                  Text(
                    '${habit.loggedCount}/$target',
                    style: theme.textTheme.labelMedium,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
