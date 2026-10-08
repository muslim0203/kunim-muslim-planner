/// The points card and the day-by-day grid on the statistics screen.
///
/// Both read only what the device already stores (`activity_providers.dart`):
/// a day is complete when every widget planned for it was done, partial when
/// some were, and missed when none were. A day with nothing planned is shown
/// as free — never as a failure.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../application/activity_providers.dart';
import '../domain/activity_history.dart';

/// Level, today's points, this week's points and the current run.
class ScoreCard extends ConsumerWidget {
  const ScoreCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final board = ref.watch(scoreBoardProvider);
    final toNext = board.pointsToNextLevel;
    final levelProgress = 1 - toNext / 500;

    return HeritageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.military_tech_outlined, color: KunimColors.gold),
              const SizedBox(width: KunimSpacing.sm),
              Expanded(
                child: Text(
                  l10n.statsPointsTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                l10n.statsLevel(board.level),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: KunimColors.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: KunimSpacing.sm),
          Text(
            l10n.statsPointsToday(board.todayPoints),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: KunimSpacing.xs),
          Wrap(
            spacing: KunimSpacing.md,
            runSpacing: KunimSpacing.xs,
            children: [
              Text(
                l10n.statsPointsWeek(board.lastWeek),
                style: theme.textTheme.bodySmall,
              ),
              if (board.streak > 0)
                Text(
                  l10n.habitStreakDays(board.streak),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: KunimSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(KunimRadii.small),
            child: LinearProgressIndicator(
              value: levelProgress.clamp(0.0, 1.0),
              minHeight: 6,
              color: KunimColors.gold,
            ),
          ),
          const SizedBox(height: KunimSpacing.xs),
          Text(
            l10n.statsToNextLevel(toNext),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One square per day of the window; tapping one opens that day's list.
class DailyAnalysisCard extends ConsumerWidget {
  const DailyAnalysisCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final history = ref.watch(activityHistoryProvider);

    return HeritageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.statsDailyIntro, style: theme.textTheme.bodySmall),
          const SizedBox(height: KunimSpacing.md),
          Wrap(
            spacing: KunimSpacing.xs,
            runSpacing: KunimSpacing.xs,
            children: [
              for (final day in history.days)
                _DaySquare(
                  day: day,
                  isToday: day.day == history.days.last.day,
                ),
            ],
          ),
          const SizedBox(height: KunimSpacing.md),
          Wrap(
            spacing: KunimSpacing.md,
            runSpacing: KunimSpacing.xs,
            children: [
              _Legend(
                  color: _dayColor(theme, _DayState.complete),
                  label: l10n.statsLegendDone),
              _Legend(
                  color: _dayColor(theme, _DayState.partial),
                  label: l10n.statsLegendPartial),
              _Legend(
                  color: _dayColor(theme, _DayState.missed),
                  label: l10n.statsLegendMissed),
              _Legend(
                  color: _dayColor(theme, _DayState.free),
                  label: l10n.statsLegendFree),
            ],
          ),
        ],
      ),
    );
  }
}

enum _DayState { complete, partial, missed, free }

_DayState _stateOf(ActivityDay day, {required bool isToday}) {
  if (day.isFree) return _DayState.free;
  if (day.isComplete) return _DayState.complete;
  // A day still being lived has not been missed. Marking today red the
  // moment it starts calls a failure on work the user still has hours to
  // do, and this app's own rule is that these indicators exist to help
  // someone decide, never to blame them (CLAUDE.md, TZ section 78).
  if (isToday) return _DayState.partial;
  return day.done == 0 ? _DayState.missed : _DayState.partial;
}

Color _dayColor(ThemeData theme, _DayState state) {
  return switch (state) {
    _DayState.complete => theme.colorScheme.primary,
    _DayState.partial => KunimColors.gold,
    _DayState.missed => theme.colorScheme.error,
    _DayState.free => theme.colorScheme.surfaceContainerHighest,
  };
}

class _DaySquare extends StatelessWidget {
  const _DaySquare({required this.day, required this.isToday});

  final ActivityDay day;

  /// Taken from the history's own last entry rather than read off the clock
  /// here, so the square and the history it came from can never disagree
  /// about which day is today.
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _stateOf(day, isToday: isToday);
    final label = MaterialLocalizations.of(context).formatMediumDate(
      DateTime(day.day.year, day.day.month, day.day.day),
    );
    // The square grows with the text so the date inside it is never clipped.
    final side = MediaQuery.textScalerOf(context).scale(15) + 14;

    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(KunimRadii.small),
        onTap: () => showDayDetails(context, day),
        child: Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _dayColor(theme, state),
            borderRadius: BorderRadius.circular(KunimRadii.small),
          ),
          child: Text(
            '${day.day.day}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: state == _DayState.free
                  ? theme.colorScheme.onSurfaceVariant
                  : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: KunimSpacing.xs),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// What was done and what was missed on one day.
Future<void> showDayDetails(BuildContext context, ActivityDay day) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final done = [
        for (final item in day.items)
          if (item.done) item
      ];
      final missed = day.missedItems;

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KunimSpacing.lg,
          0,
          KunimSpacing.lg,
          KunimSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              MaterialLocalizations.of(context).formatMediumDate(
                DateTime(day.day.year, day.day.month, day.day.day),
              ),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: KunimSpacing.xs),
            Text(
              day.isFree
                  ? l10n.statsDayFree
                  : l10n.statsDaySummary(day.done, day.planned),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (missed.isNotEmpty) ...[
              const SizedBox(height: KunimSpacing.lg),
              Text(l10n.statsDayMissedTitle, style: theme.textTheme.titleSmall),
              for (final item in missed)
                _DayItemRow(
                  title: item.title,
                  icon: Icons.close_rounded,
                  color: theme.colorScheme.error,
                ),
            ],
            if (done.isNotEmpty) ...[
              const SizedBox(height: KunimSpacing.lg),
              Text(l10n.statsDayDoneTitle, style: theme.textTheme.titleSmall),
              for (final item in done)
                _DayItemRow(
                  title: item.title,
                  icon: Icons.check_rounded,
                  color: theme.colorScheme.primary,
                ),
            ],
          ],
        ),
      );
    },
  );
}

class _DayItemRow extends StatelessWidget {
  const _DayItemRow({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KunimSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: KunimSpacing.sm),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
