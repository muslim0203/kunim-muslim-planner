/// What the analysis found, and the one thing to do about each area.
///
/// Every line here is backed by days the user can count on their own grid:
/// how many days an area was planned, how many it was done, and which way it
/// is going. Where the app has nothing recorded it says so rather than
/// filling the space with encouragement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../../habits/application/habit_repositories.dart';
import '../../habits/presentation/habit_editor.dart';
import '../../habits/presentation/widget_catalog_sheet.dart';
import '../../onboarding/presentation/onboarding_labels.dart';
import '../application/insight_providers.dart';
import '../domain/area_insight.dart';

class InsightsView extends ConsumerWidget {
  const InsightsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final insights = ref.watch(areaInsightsProvider);

    if (insights.isEmpty) {
      return HeritageCard(
        child: Row(
          children: [
            Icon(Icons.insights_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: KunimSpacing.md),
            Expanded(
              child:
                  Text(l10n.insightsEmpty, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      );
    }

    final weakest = insights.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.insightsWindow(insightWindowDays),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: KunimSpacing.xs),
        Text(
          weakest.state == AreaState.strong
              ? l10n.insightsAllWell
              : l10n.insightsWeakest(focusAreaLabel(l10n, weakest.area)),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: KunimSpacing.md),
        for (final insight in insights) ...[
          _AreaCard(insight: insight),
          const SizedBox(height: KunimSpacing.sm),
        ],
      ],
    );
  }
}

class _AreaCard extends ConsumerWidget {
  const _AreaCard({required this.insight});

  final AreaInsight insight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colour = _stateColour(theme, insight.state);

    return HeritageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(focusAreaIcon(insight.area), color: colour),
              const SizedBox(width: KunimSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      focusAreaLabel(l10n, insight.area),
                      style: theme.textTheme.titleSmall,
                    ),
                    // Which widget the advice is really about: an area can
                    // hold several, and "lower the daily amount" has to say
                    // whose amount.
                    if (insight.title.isNotEmpty)
                      Text(
                        insight.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              _StateChip(state: insight.state, colour: colour),
            ],
          ),
          const SizedBox(height: KunimSpacing.xs),
          Text(
            insight.plannedDays == 0
                ? l10n.insightsAdviceAddWidget
                : l10n.insightsDaysDone(insight.doneDays, insight.plannedDays),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (insight.trend != 0 && insight.plannedDays > 0) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  insight.trend > 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  insight.trend > 0
                      ? l10n.insightsTrendUp
                      : l10n.insightsTrendDown,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          if (insight.advice != AreaAdvice.addWidget ||
              insight.plannedDays > 0) ...[
            const SizedBox(height: KunimSpacing.sm),
            Text(_adviceText(l10n, insight.advice)),
          ],
          if (_action(context, ref, l10n) case final action?) ...[
            const SizedBox(height: KunimSpacing.sm),
            Align(alignment: AlignmentDirectional.centerStart, child: action),
          ],
        ],
      ),
    );
  }

  /// The one tap this card is worth. Advice with no action behind it is a
  /// sentence, not help.
  Widget? _action(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    switch (insight.advice) {
      case AreaAdvice.keepGoing:
        return null;
      case AreaAdvice.addWidget:
        return FilledButton.tonalIcon(
          onPressed: () => showWidgetCatalog(context),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.homeWidgetAdd),
        );
      case AreaAdvice.lowerTarget:
      case AreaAdvice.moveTime:
      case AreaAdvice.startAgain:
        final habitId = insight.habitId;
        if (habitId == null) {
          // The prayers have no widget; their own screen is the place.
          return FilledButton.tonalIcon(
            onPressed: () => context.go(KunimRoutes.prayer),
            icon: const Icon(Icons.mosque_outlined),
            label: Text(l10n.insightsOpenPrayers),
          );
        }
        return FilledButton.tonalIcon(
          onPressed: () => _openWidget(context, ref, habitId),
          icon: const Icon(Icons.tune_rounded),
          label: Text(l10n.insightsOpenWidget),
        );
    }
  }

  Future<void> _openWidget(
    BuildContext context,
    WidgetRef ref,
    String habitId,
  ) async {
    final habit = await ref.read(habitRepositoryProvider).findById(habitId);
    if (!context.mounted || habit == null) return;
    await showHabitEditor(context, habit: habit);
  }

  static String _adviceText(AppLocalizations l10n, AreaAdvice advice) {
    return switch (advice) {
      AreaAdvice.keepGoing => l10n.insightsAdviceKeepGoing,
      AreaAdvice.lowerTarget => l10n.insightsAdviceLowerTarget,
      AreaAdvice.moveTime => l10n.insightsAdviceMoveTime,
      AreaAdvice.startAgain => l10n.insightsAdviceStartAgain,
      AreaAdvice.addWidget => l10n.insightsAdviceAddWidget,
    };
  }

  static Color _stateColour(ThemeData theme, AreaState state) {
    return switch (state) {
      AreaState.strong => theme.colorScheme.primary,
      AreaState.steady => theme.colorScheme.tertiary,
      AreaState.slipping => theme.colorScheme.error,
      AreaState.untouched => theme.colorScheme.onSurfaceVariant,
    };
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state, required this.colour});

  final AreaState state;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = switch (state) {
      AreaState.strong => l10n.insightsStateStrong,
      AreaState.steady => l10n.insightsStateSteady,
      AreaState.slipping => l10n.insightsStateSlipping,
      AreaState.untouched => l10n.insightsStateUntouched,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: colour),
      ),
    );
  }
}
