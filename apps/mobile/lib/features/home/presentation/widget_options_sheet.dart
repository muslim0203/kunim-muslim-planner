/// What a home widget offers besides today's one tap: its settings, its
/// life-area screen, and undoing today.
///
/// Held (long-pressed) from the grid, so the tile itself stays a single tap
/// for the thing done every day.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../habits/application/habits_today_provider.dart';
import '../../habits/domain/habit_kind.dart';
import '../../habits/presentation/habit_editor.dart';
import '../../habits/presentation/habit_kind_labels.dart';

Future<void> showWidgetOptions(BuildContext context, HabitToday habit) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => WidgetOptionsSheet(habit: habit),
  );
}

class WidgetOptionsSheet extends ConsumerWidget {
  const WidgetOptionsSheet({super.key, required this.habit});

  final HabitToday habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final kind = HabitKind.fromCode(habit.habit.kind);
    final route = habitKindRoute(kind);
    final time = habitTimeOfDay(habit.habit.reminderMinutes);

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KunimSpacing.lg,
              0,
              KunimSpacing.lg,
              KunimSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(habit.habit.title, style: theme.textTheme.titleLarge),
                Text(
                  time == null
                      ? l10n.habitTimeNone
                      : MaterialLocalizations.of(context).formatTimeOfDay(
                          time,
                          alwaysUse24HourFormat: true,
                        ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(
              habit.isDone
                  ? Icons.remove_circle_outline_rounded
                  : Icons.check_circle_outline_rounded,
            ),
            title: Text(
              habit.isDone ? l10n.habitUndoToday : l10n.habitLogToday,
            ),
            onTap: () {
              Navigator.of(context).pop();
              toggleHabitToday(ref, habit);
            },
          ),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: Text(l10n.habitEdit),
            onTap: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              showHabitEditor(navigator.context, habit: habit.habit);
            },
          ),
          if (route != null)
            ListTile(
              leading: Icon(habitKindIcon(kind)),
              title: Text(habitKindName(l10n, kind)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.go(route);
              },
            ),
          const SizedBox(height: KunimSpacing.md),
        ],
      ),
    );
  }
}
