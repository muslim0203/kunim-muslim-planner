/// The home grid: the user's own daily widgets.
///
/// Life areas and "today's habits" used to be two separate sections; they
/// are one here. Every tile is a widget the user set up (a book, zikr,
/// sport, ...) showing today's progress and, when it has one, the time its
/// task belongs to. Tapping a tile does today's work; holding it opens the
/// widget's options, including the life-area screen it belongs to.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/fit_word_text.dart';
import '../../habits/application/habits_today_provider.dart';
import '../../habits/domain/habit_kind.dart';
import '../../habits/presentation/habit_editor.dart';
import '../../habits/presentation/habit_kind_labels.dart';
import '../../habits/presentation/widget_catalog_sheet.dart';
import 'module_sheet.dart';
import 'widget_options_sheet.dart';

class HomeWidgetGrid extends StatelessWidget {
  const HomeWidgetGrid({super.key, required this.habits});

  final AsyncValue<List<HabitToday>> habits;

  static const double _gap = KunimSpacing.sm;
  static const double tilePadding = KunimSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final items = habits.value ?? const <HabitToday>[];
    final titleStyle = WidgetTile.titleStyle(theme);
    final largeText = MediaQuery.textScalerOf(context).scale(10) > 13;

    final tiles = <Widget Function(double contentWidth)>[
      for (final habit in items)
        (width) => WidgetTile(habit: habit, contentWidth: width),
      (width) => ActionTile(
            icon: Icons.add_rounded,
            label: l10n.homeWidgetAdd,
            contentWidth: width,
            onTap: () => showWidgetCatalog(context),
          ),
      (width) => ActionTile(
            icon: Icons.apps_rounded,
            label: l10n.homeAllModules,
            contentWidth: width,
            onTap: () => showModuleSheet(context),
          ),
    ];
    final labels = [
      for (final habit in items) habit.habit.title,
      l10n.homeWidgetAdd,
      l10n.homeAllModules,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty) ...[
          Text(
            l10n.homeWidgetsEmpty,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: KunimSpacing.sm),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            double contentWidthFor(int columns) =>
                (constraints.maxWidth - _gap * (columns - 1)) / columns -
                tilePadding * 2;

            // Four narrow tiles only while every label fits one at a
            // readable size, without a broken word; otherwise two wide ones
            // (a long widget name needs them).
            var perRow = largeText ? 2 : 4;
            if (perRow == 4) {
              final narrow = contentWidthFor(4);
              final fits = labels.every(
                (label) => FitWordText.fitsWithin(
                  context,
                  label,
                  titleStyle,
                  narrow,
                  maxLines: WidgetTile.titleMaxLines,
                ),
              );
              if (!fits) perRow = 2;
            }
            final contentWidth = contentWidthFor(perRow);
            return Column(
              children: [
                for (var start = 0; start < tiles.length; start += perRow)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: start + perRow < tiles.length ? _gap : 0,
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = start; i < start + perRow; i++) ...[
                            if (i > start) const SizedBox(width: _gap),
                            Expanded(
                              child: i < tiles.length
                                  ? tiles[i](contentWidth)
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One widget: icon, name, today's progress and its time.
class WidgetTile extends ConsumerWidget {
  const WidgetTile({
    super.key,
    required this.habit,
    required this.contentWidth,
  });

  final HabitToday habit;
  final double contentWidth;

  static const int titleMaxLines = 2;

  static TextStyle titleStyle(ThemeData theme) =>
      theme.textTheme.labelMedium!.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.15,
      );

  static TextStyle metaStyle(ThemeData theme) =>
      theme.textTheme.labelSmall!.copyWith(
        height: 1.15,
        color: theme.colorScheme.onSurfaceVariant,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = HabitKind.fromCode(habit.habit.kind);
    final target = habit.habit.targetCount;
    final time = habitTimeOfDay(habit.habit.reminderMinutes);
    final done = habit.isDone;

    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KunimRadii.medium),
        side: BorderSide(
          color: done ? habitKindColor(kind) : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => toggleHabitToday(ref, habit),
        onLongPress: () => showWidgetOptions(context, habit),
        child: Padding(
          padding: const EdgeInsets.all(HomeWidgetGrid.tilePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: habitKindColor(kind),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      done ? Icons.check_rounded : habitKindIcon(kind),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  if (time != null)
                    Text(
                      MaterialLocalizations.of(context).formatTimeOfDay(
                        time,
                        alwaysUse24HourFormat: true,
                      ),
                      style: metaStyle(theme),
                    ),
                ],
              ),
              const SizedBox(height: KunimSpacing.md),
              FitWordText(
                habit.habit.title,
                maxWidth: contentWidth,
                maxLines: titleMaxLines,
                style: titleStyle(theme),
              ),
              const SizedBox(height: 2),
              Text(
                target > 1
                    ? '${habit.loggedCount}/$target'
                    : habitAmount(l10n, kind, target),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: metaStyle(theme),
              ),
              if (target > 1) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: (habit.loggedCount / target).clamp(0.0, 1.0),
                  minHeight: 4,
                  color: habitKindColor(kind),
                  borderRadius: BorderRadius.circular(99),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Add a widget" / "All sections": the two tiles that are not a widget.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.contentWidth,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final double contentWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KunimRadii.medium),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(HomeWidgetGrid.tilePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: scheme.onSurfaceVariant, size: 20),
              ),
              const SizedBox(height: KunimSpacing.md),
              FitWordText(
                label,
                maxWidth: contentWidth,
                maxLines: WidgetTile.titleMaxLines,
                style: WidgetTile.titleStyle(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
