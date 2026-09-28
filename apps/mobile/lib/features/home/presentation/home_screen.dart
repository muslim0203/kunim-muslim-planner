import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/db/app_database.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../../habits/application/habits_today_provider.dart';
import '../../prayer/application/prayer_providers.dart';
import '../../prayer/domain/daily_prayer_times.dart';
import '../../prayer/presentation/prayer_labels.dart';
import '../../tasks/application/task_mutation_controller.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/application/top_three_providers.dart';
import '../../tasks/domain/task_status.dart';
import 'widget_grid.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scroll = ScrollController();

  /// Whether the status bar currently sits over the hero photo (light icons)
  /// or over the plain page background (icons matching the theme).
  final ValueNotifier<bool> _statusBarOverHero = ValueNotifier<bool>(true);
  double _heroScrollExtent = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateStatusBar);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_updateStatusBar)
      ..dispose();
    _statusBarOverHero.dispose();
    super.dispose();
  }

  void _updateStatusBar() {
    _statusBarOverHero.value =
        !_scroll.hasClients || _scroll.offset < _heroScrollExtent;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.watch(todayTasksProvider);
    final topThree = ref.watch(topThreeTasksProvider);
    final habits = ref.watch(habitsForTodayProvider);
    final padding = MediaQuery.paddingOf(context);

    _heroScrollExtent =
        _HeroAndPrayerStrip.heroHeightFor(context) - padding.top;

    return ValueListenableBuilder<bool>(
      valueListenable: _statusBarOverHero,
      builder: (context, overHero, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: kunimOverlayStyleFor(
            overHero ? Brightness.dark : Theme.of(context).brightness,
          ),
          child: child!,
        );
      },
      child: Scaffold(
        body: Stack(
          children: [
            _buildList(context, l10n, tasks, topThree, habits, padding),
            // Once the photo has scrolled away, page content would otherwise
            // run underneath the clock and status icons.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: padding.top,
              child: ValueListenableBuilder<bool>(
                valueListenable: _statusBarOverHero,
                builder: (context, overHero, _) => overHero
                    ? const SizedBox.shrink()
                    : ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    AppLocalizations l10n,
    AsyncValue<List<Task>> tasks,
    AsyncValue<List<Task>> topThree,
    AsyncValue<List<HabitToday>> habits,
    EdgeInsets padding,
  ) {
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.only(bottom: KunimSpacing.xl + padding.bottom),
      children: [
        const _HeroAndPrayerStrip(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KunimSpacing.lg,
            KunimSpacing.md,
            KunimSpacing.lg,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TodayProgress(tasks: tasks),
              const SizedBox(height: KunimSpacing.lg),
              _SectionHeader(
                title: l10n.homeModules,
                action: l10n.habitManage,
                onAction: () => context.go(KunimRoutes.habits),
              ),
              _WidgetProgressLine(habits: habits),
              const SizedBox(height: KunimSpacing.md),
              HomeWidgetGrid(habits: habits),
              const SizedBox(height: KunimSpacing.xl),
              _SectionHeader(
                title: l10n.homeMainTasks,
                action: l10n.homeSeeAll,
                onAction: () => context.go(KunimRoutes.day),
              ),
              const SizedBox(height: KunimSpacing.sm),
              _MainTasksCard(tasks: topThree),
              const SizedBox(height: KunimSpacing.lg),
              const _DailyInsight(),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroAndPrayerStrip extends StatelessWidget {
  const _HeroAndPrayerStrip();

  /// How far the prayer strip overlaps the bottom of the photo.
  static const double _overlap = 40;

  /// The photo grows with the text scale so its copy never runs out of room.
  static double heroHeightFor(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    return topInset + 244 * scale.clamp(1.0, 2.5);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final topInset = MediaQuery.paddingOf(context).top;
    final heroHeight = heroHeightFor(context);

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: heroHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The mosque sits at the right edge of a wide panorama; align
              // the crop there so it is not cut off on a portrait phone.
              Image.asset(
                'assets/images/home-dawn-v1.webp',
                fit: BoxFit.cover,
                alignment: const Alignment(0.8, 0),
                excludeFromSemantics: true,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xD90B1F2A),
                      Color(0x65102C37),
                      Color(0x18102C37),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  topInset + 18,
                  20,
                  _overlap + KunimSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  // No Spacer next to the Flexible title: a Spacer and a
                  // Flexible split the free height evenly, which clipped the
                  // title to half of its second line.
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.aiGreeting,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: KunimSpacing.xs),
                          Flexible(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 300),
                              child: Text(
                                l10n.homeOpportunity,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.headlineMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: KunimSpacing.sm),
                    const _DateChip(),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            KunimSpacing.md,
            heroHeight - _overlap,
            KunimSpacing.md,
            0,
          ),
          child: const _PrayerStrip(),
        ),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(KunimRadii.medium),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              MaterialLocalizations.of(context)
                  .formatMediumDate(DateTime.now()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// All six times side by side for the chosen city, with the next one
/// highlighted. Until a city is chosen they stay as placeholders. Tapping
/// opens the prayer screen either way.
class _PrayerStrip extends ConsumerWidget {
  const _PrayerStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final day = ref.watch(todayPrayerProvider).value;
    final radius = BorderRadius.circular(KunimRadii.large);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x140B1F2A),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(KunimRoutes.prayer),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: KunimSpacing.md,
              horizontal: KunimSpacing.xs,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final kind in PrayerKind.values) ...[
                    if (kind.index > 0)
                      VerticalDivider(width: 1, color: scheme.outlineVariant),
                    Expanded(
                      child: _PrayerCell(
                        kind: kind,
                        time: day?.slots[kind.index].time,
                        isNext: day?.nextIndex == kind.index,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrayerCell extends StatelessWidget {
  const _PrayerCell({
    required this.kind,
    required this.time,
    required this.isNext,
  });

  final PrayerKind kind;

  /// `null` while no city is chosen.
  final DateTime? time;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = PrayerLabels.prayer(l10n, kind);
    final time = this.time;
    final timeText = time == null ? '—:—' : PrayerLabels.time(context, time);
    final accent = isNext ? scheme.primary : null;
    final weight = isNext ? FontWeight.w800 : null;

    return Semantics(
      label: '$name, ${time == null ? l10n.prayerPending : timeText}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PrayerLabels.icon(kind),
            color: isNext ? scheme.primary : scheme.secondary,
            size: 22,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              name,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: weight,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              timeText,
              maxLines: 1,
              style: theme.textTheme.labelLarge?.copyWith(
                color: accent,
                fontWeight: weight,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isNext ? scheme.primary : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayProgress extends StatelessWidget {
  const _TodayProgress({required this.tasks});

  final AsyncValue<List<Task>> tasks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final items = tasks.value ?? const <Task>[];
    final total = items.length;
    final completed = items.where((task) => task.isCompleted).length;
    final progress = total == 0 ? 0.0 : completed / total;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(KunimRadii.large),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient:
              LinearGradient(colors: [KunimColors.jade, Color(0xFF087666)]),
        ),
        child: InkWell(
          onTap: () => context.go(KunimRoutes.day),
          child: Padding(
            padding: const EdgeInsets.all(KunimSpacing.lg),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 72,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 7,
                          strokeCap: StrokeCap.round,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '$completed/$total',
                            style: textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: KunimSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.homeProgress,
                        style: textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: KunimSpacing.xs),
                      Text(
                        total == 0
                            ? l10n.homeNothingPlanned
                            : l10n.homeProgressSummary(completed, total),
                        style: textTheme.bodyMedium?.copyWith(
                          color: KunimColors.jadeSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "3/8 done" under the grid's header, so the day's state reads at a glance.
class _WidgetProgressLine extends StatelessWidget {
  const _WidgetProgressLine({required this.habits});

  final AsyncValue<List<HabitToday>> habits;

  @override
  Widget build(BuildContext context) {
    final items = habits.value ?? const <HabitToday>[];
    if (items.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final done = items.where((habit) => habit.isDone).length;
    return Text(
      l10n.homeWidgetsDoneOf(done, items.length),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

class _MainTasksCard extends ConsumerWidget {
  const _MainTasksCard({required this.tasks});

  final AsyncValue<List<Task>> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return HeritageCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: tasks.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.errorGeneric),
        ),
        data: (items) {
          if (items.isEmpty) {
            return ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: Text(l10n.homeChooseTopThree),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.go(KunimRoutes.day),
            );
          }
          return Column(
            children: [
              for (final task in items.take(5)) _CompactTaskRow(task: task),
            ],
          );
        },
      ),
    );
  }
}

class _CompactTaskRow extends ConsumerWidget {
  const _CompactTaskRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = task.isCompleted;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Semantics(
            label: done ? l10n.taskMarkIncomplete : l10n.taskMarkComplete,
            child: Checkbox(
              value: done,
              onChanged: (_) {
                final controller =
                    ref.read(taskMutationControllerProvider.notifier);
                done
                    ? controller.uncompleteTask(task.id)
                    : controller.completeTask(task.id);
              },
            ),
          ),
          Expanded(
            child: Text(
              task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (task.isOverdue())
            Icon(Icons.schedule_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

class _DailyInsight extends StatelessWidget {
  const _DailyInsight();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(KunimSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(KunimRadii.large),
      ),
      child: Row(
        children: [
          Icon(Icons.eco_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: KunimSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.homeDailyInsight, style: theme.textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  l10n.homeDailyInsightMeta,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
