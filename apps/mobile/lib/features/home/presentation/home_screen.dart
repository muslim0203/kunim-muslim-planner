/// The Home tab: greeting, the manually chosen Top-3, today's tasks and
/// today's habits. The phase-2 Definition of Done names exactly these three
/// blocks; the AI-ranked variant arrives in phase 7.
///
/// This screen only reads providers and renders. No database access, no
/// merge logic, and no hardcoded user-visible text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/db/app_database.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/kunim_card.dart';
import '../../habits/application/habit_mutation_controller.dart';
import '../../habits/application/habits_today_provider.dart';
import '../../tasks/application/task_mutation_controller.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/application/top_three_providers.dart';
import '../../tasks/domain/task_status.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(KunimSpacing.lg),
          children: [
            Text(
              // TODO(profile): pass the signed-in user's display name once a
              // profile provider exists on the client.
              l10n.homeGreeting(''),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: KunimSpacing.lg),
            const _TopThreeSection(),
            const SizedBox(height: KunimSpacing.lg),
            const _TodaysPlanSection(),
            const SizedBox(height: KunimSpacing.lg),
            const _TodaysHabitsSection(),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KunimSpacing.sm),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _TopThreeSection extends ConsumerWidget {
  const _TopThreeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final topThree = ref.watch(topThreeTasksProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(l10n.homeTopThree),
        topThree.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => EmptyState(message: l10n.errorGeneric),
          data: (tasks) {
            if (tasks.isEmpty) {
              return EmptyState(
                message: l10n.homeChooseTopThree,
                icon: Icons.star_outline,
              );
            }
            return Column(
              children: [
                for (final task in tasks)
                  _TaskTile(task: task, accent: KunimModuleColors.work),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TodaysPlanSection extends ConsumerWidget {
  const _TodaysPlanSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.watch(todayTasksProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(l10n.homeTodaysPlan),
        tasks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => EmptyState(message: l10n.errorGeneric),
          data: (items) {
            if (items.isEmpty) {
              return EmptyState(
                message: l10n.homeNothingPlanned,
                icon: Icons.event_available_outlined,
              );
            }
            return Column(
              children: [for (final task in items) _TaskTile(task: task)],
            );
          },
        ),
      ],
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, this.accent});

  final Task task;
  final Color? accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final done = task.isCompleted;

    return Padding(
      padding: const EdgeInsets.only(bottom: KunimSpacing.sm),
      child: KunimCard(
        accentColor: accent,
        padding: const EdgeInsets.symmetric(
          horizontal: KunimSpacing.md,
          vertical: KunimSpacing.xs,
        ),
        child: Row(
          children: [
            Semantics(
              label: done ? l10n.taskMarkIncomplete : l10n.taskMarkComplete,
              child: Checkbox(
                value: done,
                onChanged: (_) {
                  final controller = ref.read(
                    taskMutationControllerProvider.notifier,
                  );
                  // Rule 8: completed_at is max-wins on the server, so
                  // un-completing may not survive a merge against a device
                  // that completed it later. That is deliberate.
                  if (done) {
                    controller.uncompleteTask(task.id);
                  } else {
                    controller.completeTask(task.id);
                  }
                },
              ),
            ),
            Expanded(
              child: Text(
                task.title,
                style: done
                    ? TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: Theme.of(context).disabledColor,
                      )
                    : null,
              ),
            ),
            if (task.isOverdue())
              Padding(
                padding: const EdgeInsets.only(left: KunimSpacing.sm),
                child: Text(
                  l10n.taskOverdue,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodaysHabitsSection extends ConsumerWidget {
  const _TodaysHabitsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final habits = ref.watch(habitsForTodayProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(l10n.homeTodaysHabits),
        habits.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => EmptyState(message: l10n.errorGeneric),
          data: (items) {
            if (items.isEmpty) {
              return EmptyState(
                message: l10n.habitEmptyState,
                icon: Icons.check_circle_outline,
              );
            }
            return Column(
              children: [for (final item in items) _HabitTile(item: item)],
            );
          },
        ),
      ],
    );
  }
}

class _HabitTile extends ConsumerWidget {
  const _HabitTile({required this.item});

  final HabitToday item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final target = item.habit.targetCount;
    final reached = target > 0 && item.loggedCount >= target;

    return Padding(
      padding: const EdgeInsets.only(bottom: KunimSpacing.sm),
      child: KunimCard(
        accentColor: KunimModuleColors.health,
        padding: const EdgeInsets.symmetric(
          horizontal: KunimSpacing.md,
          vertical: KunimSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(child: Text(item.habit.title)),
            Text('${item.loggedCount}/$target'),
            const SizedBox(width: KunimSpacing.sm),
            Semantics(
              label: l10n.habitLogToday,
              button: true,
              child: IconButton(
                icon: Icon(
                  reached ? Icons.check_circle : Icons.add_circle_outline,
                ),
                color: reached ? KunimModuleColors.health : null,
                onPressed: () {
                  ref
                      .read(habitMutationControllerProvider.notifier)
                      .logCompletion(habitId: item.habit.id, day: item.day);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
