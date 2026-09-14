import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/daily_log_screen.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../../habits/domain/streak.dart';
import '../application/weekly_stats_provider.dart';
import '../application/wellbeing_week_provider.dart';
import '../domain/weekly_stats.dart';
import '../domain/wellbeing_week.dart';

/// Weekly statistics from real local data only. Areas without a data source
/// yet are shown as coming soon, never with sample numbers.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final stats = ref.watch(weeklyStatsProvider);
    final wellbeing = ref.watch(wellbeingWeekProvider).value;

    return KunimStatusBarRegion(
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(KunimSpacing.lg),
            children: [
              ScreenIntro(
                eyebrow: l10n.statsPeriod,
                title: l10n.statsGrowthTitle,
                subtitle: l10n.statsGrowthSubtitle,
              ),
              const SizedBox(height: KunimSpacing.xl),
              ...stats.when(
                loading: () => const [
                  Padding(
                    padding: EdgeInsets.all(KunimSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (_, __) => [Text(l10n.errorGeneric)],
                data: (data) => _content(context, data, wellbeing),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    WeeklyStats stats,
    WellbeingWeek? wellbeing,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return [
      if (stats.hasData)
        _ConsistencyCard(stats: stats)
      else
        const _NoDataCard(),
      const SizedBox(height: KunimSpacing.xl),
      Text(l10n.statsDirections, style: theme.textTheme.titleLarge),
      const SizedBox(height: KunimSpacing.md),
      _AreasCard(stats: stats, wellbeing: wellbeing),
      if (stats.hasData) ...[
        const SizedBox(height: KunimSpacing.lg),
        _Highlights(stats: stats),
      ],
      const SizedBox(height: KunimSpacing.md),
      Text(
        l10n.statsTrackingSoon,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }
}

class _ConsistencyCard extends StatelessWidget {
  const _ConsistencyCard({required this.stats});

  final WeeklyStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final percent = stats.consistencyPercent ?? 0;
    final previous = stats.previousWeekPercent;

    return Container(
      padding: const EdgeInsets.all(KunimSpacing.xl),
      decoration: BoxDecoration(
        color: KunimColors.ink,
        borderRadius: BorderRadius.circular(KunimRadii.extraLarge),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.statsWeeklyStability,
                  style: textTheme.labelSmall?.copyWith(
                    color: KunimColors.goldSoft,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: KunimSpacing.md),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$percent%',
                    style: textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: KunimSpacing.xs),
                Text(
                  previous == null
                      ? l10n.statsNoPreviousWeek
                      : l10n.statsPreviousWeek(previous),
                  style: textTheme.bodySmall?.copyWith(
                    color: KunimColors.jadeSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: KunimSpacing.lg),
          SizedBox.square(
            dimension: 88,
            child: CircularProgressIndicator(
              value: percent / 100,
              strokeWidth: 10,
              strokeCap: StrokeCap.round,
              color: KunimColors.gold,
              backgroundColor: Colors.white12,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoDataCard extends StatelessWidget {
  const _NoDataCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return HeritageCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.insights_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: KunimSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.statsNoDataTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: KunimSpacing.xs),
                Text(
                  l10n.statsNoDataBody,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AreasCard extends StatelessWidget {
  const _AreasCard({required this.stats, required this.wellbeing});

  final WeeklyStats stats;

  /// `null` while the daily log streams are still loading.
  final WellbeingWeek? wellbeing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final week = wellbeing;
    final format = _StatsNumbers(l10n);

    return HeritageCard(
      child: Column(
        children: [
          _ProgressRow(
            label: l10n.taskScreenTitle,
            done: stats.tasksDone,
            total: stats.tasksPlanned,
            color: KunimModuleColors.work,
          ),
          _ProgressRow(
            label: l10n.habitScreenTitle,
            done: stats.habitsDone,
            total: stats.habitsScheduled,
            color: KunimModuleColors.mood,
          ),
          const Divider(height: KunimSpacing.xl),
          _WellbeingRow(
            label: l10n.moduleMood,
            icon: Icons.spa_outlined,
            color: KunimModuleColors.mood,
            days: week?.moodDays ?? 0,
            details: [
              if (week?.moodAverage != null)
                l10n.statsMoodAverage(format.decimal(week!.moodAverage!)),
            ],
            onTap: () => context.go(KunimRoutes.mood),
          ),
          _WellbeingRow(
            label: l10n.statsSleep,
            icon: Icons.bedtime_outlined,
            color: KunimModuleColors.sleep,
            days: week?.sleepNights ?? 0,
            details: [
              if (week?.sleepAverageMin != null)
                l10n.statsSleepAverage(
                  formatLogDuration(l10n, week!.sleepAverageMin!),
                ),
              if (week?.sleepQualityAverage != null)
                l10n.statsSleepQuality(
                  format.decimal(week!.sleepQualityAverage!),
                ),
            ],
            onTap: () => context.go(KunimRoutes.sleep),
          ),
          _WellbeingRow(
            label: l10n.statsHealth,
            icon: Icons.fitness_center_rounded,
            color: KunimModuleColors.health,
            days: week?.healthDays ?? 0,
            details: [
              if (week?.waterAverageMl != null)
                l10n.statsWaterAverage(format.integer(week!.waterAverageMl!)),
              if (week?.stepsAverage != null)
                l10n.statsStepsAverage(format.integer(week!.stepsAverage!)),
              if (week?.workoutTotalMin != null)
                l10n.statsWorkoutTotal(
                  formatLogDuration(l10n, week!.workoutTotalMin!),
                ),
            ],
            onTap: () => context.go(KunimRoutes.health),
          ),
          _WellbeingRow(
            label: l10n.moduleFamily,
            icon: Icons.favorite_outline_rounded,
            color: KunimModuleColors.family,
            days: week?.familyDays ?? 0,
            details: [
              if (week?.familyTotalMin != null)
                l10n.statsFamilyTotal(
                  formatLogDuration(l10n, week!.familyTotalMin!),
                ),
            ],
            onTap: () => context.go(KunimRoutes.family),
          ),
          const Divider(height: KunimSpacing.xl),
          _ComingSoonRow(
            label: l10n.statsPrayer,
            icon: Icons.mosque_outlined,
            color: KunimModuleColors.prayer,
          ),
          _ComingSoonRow(
            label: l10n.statsQuran,
            icon: Icons.menu_book_rounded,
            color: KunimModuleColors.quran,
          ),
        ],
      ),
    );
  }
}

/// Locale-aware number formatting for the statistics rows ("8 000",
/// "4,5"). Falls back to English symbols for a locale `intl` lacks.
class _StatsNumbers {
  _StatsNumbers(AppLocalizations l10n)
      : _locale = Intl.verifiedLocale(
          l10n.localeName,
          NumberFormat.localeExists,
          onFailure: (_) => 'en',
        );

  final String? _locale;

  String integer(int value) =>
      NumberFormat.decimalPattern(_locale).format(value);

  String decimal(double value) => NumberFormat('0.0', _locale).format(value);
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.done,
    required this.total,
    required this.color,
  });

  final String label;
  final int done;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: KunimSpacing.lg),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: textTheme.labelLarge)),
              Text(total == 0 ? '—' : '$done/$total'),
            ],
          ),
          const SizedBox(height: KunimSpacing.sm),
          LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 7,
            borderRadius: BorderRadius.circular(99),
            color: color,
          ),
        ],
      ),
    );
  }
}

/// One daily log area: how many days were recorded this week and what the
/// entries add up to. Tapping opens the module.
class _WellbeingRow extends StatelessWidget {
  const _WellbeingRow({
    required this.label,
    required this.icon,
    required this.color,
    required this.days,
    required this.details,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final int days;
  final List<String> details;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final summary = days == 0
        ? l10n.statsNoEntriesWeek
        : [l10n.statsDaysCount(days), ...details].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KunimRadii.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: KunimSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: KunimSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: KunimSpacing.sm),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComingSoonRow extends StatelessWidget {
  const _ComingSoonRow({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KunimSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: KunimSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: KunimSpacing.sm),
          const ComingSoonBadge(),
        ],
      ),
    );
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights({required this.stats});

  final WeeklyStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final best = stats.bestDay;
    final bestRatio = best?.ratio;

    final streakValue = switch (stats.bestStreakUnit) {
      StreakUnit.day => l10n.statsDaysCount(stats.bestStreak),
      StreakUnit.week => l10n.statsWeeksCount(stats.bestStreak),
      null => '—',
    };

    final streak = MetricTile(
      label: l10n.statsStreak,
      value: streakValue,
      color: KunimModuleColors.prayer,
    );
    final bestDay = MetricTile(
      label: l10n.statsBestDay,
      value: bestRatio == null ? '—' : '${(bestRatio * 100).round()}%',
      caption: best == null ? null : _weekdayName(l10n, best.day.weekday),
      progress: bestRatio,
      color: KunimModuleColors.work,
    );

    final largeText = MediaQuery.textScalerOf(context).scale(10) > 13;
    if (largeText) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [streak, const SizedBox(height: KunimSpacing.md), bestDay],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: streak),
          const SizedBox(width: KunimSpacing.md),
          Expanded(child: bestDay),
        ],
      ),
    );
  }

  static String _weekdayName(AppLocalizations l10n, int weekday) {
    return switch (weekday) {
      DateTime.monday => l10n.calWeekdayMonday,
      DateTime.tuesday => l10n.calWeekdayTuesday,
      DateTime.wednesday => l10n.calWeekdayWednesday,
      DateTime.thursday => l10n.calWeekdayThursday,
      DateTime.friday => l10n.calWeekdayFriday,
      DateTime.saturday => l10n.calWeekdaySaturday,
      _ => l10n.calWeekdaySunday,
    };
  }
}
