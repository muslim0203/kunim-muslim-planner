/// Building blocks shared by the daily log modules (mood, sleep, health,
/// family): the screen layout (today on top, earlier days below), the editor
/// sheet frame, and small formatting helpers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/gen/app_localizations.dart';
import '../../app/theme/tokens.dart';
import '../../core/db/daily_log_fields.dart';
import 'kunim_widgets.dart';

class DailyLogScreen<T> extends StatelessWidget {
  const DailyLogScreen({
    super.key,
    required this.title,
    required this.intro,
    required this.today,
    required this.recent,
    required this.dateOf,
    required this.summaryOf,
    required this.onEdit,
    this.footer,
  });

  final String title;
  final String intro;

  /// Today's entry, `null` when there is none.
  final AsyncValue<T?> today;

  /// Recent entries, newest first. Today's entry is shown above instead.
  final AsyncValue<List<T>> recent;

  /// The entry's day as stored: a UTC-midnight date tag.
  final DateTime Function(T entry) dateOf;
  final Widget Function(BuildContext context, T entry) summaryOf;

  /// Opens the editor for [entry], or for a new entry today when `null`.
  final void Function(T? entry) onEdit;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final todayEntry = today.value;
    final earlier = [
      for (final entry in recent.value ?? <T>[])
        if (!isTodayTag(dateOf(entry))) entry,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(KunimSpacing.lg),
        children: [
          Text(
            intro,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: KunimSpacing.lg),
          Text(l10n.logToday, style: theme.textTheme.titleMedium),
          const SizedBox(height: KunimSpacing.sm),
          HeritageCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: todayEntry == null
                  ? [
                      Text(
                        l10n.logTodayEmpty,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: KunimSpacing.md),
                      FilledButton.icon(
                        onPressed: () => onEdit(null),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(l10n.logAdd),
                      ),
                    ]
                  : [
                      summaryOf(context, todayEntry),
                      const SizedBox(height: KunimSpacing.md),
                      OutlinedButton.icon(
                        onPressed: () => onEdit(todayEntry),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(l10n.logEdit),
                      ),
                    ],
            ),
          ),
          const SizedBox(height: KunimSpacing.xl),
          Text(l10n.logRecent, style: theme.textTheme.titleMedium),
          const SizedBox(height: KunimSpacing.sm),
          if (earlier.isEmpty)
            Text(
              l10n.logRecentEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            )
          else
            for (final entry in earlier)
              Padding(
                padding: const EdgeInsets.only(bottom: KunimSpacing.sm),
                child: HeritageCard(
                  onTap: () => onEdit(entry),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dailyLogDayTitle(context, dateOf(entry)),
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: KunimSpacing.xs),
                            summaryOf(context, entry),
                          ],
                        ),
                      ),
                      const SizedBox(width: KunimSpacing.sm),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
          if (footer != null) ...[
            const SizedBox(height: KunimSpacing.lg),
            Text(
              footer!,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Whether a UTC-midnight date tag is today's local calendar day.
bool isTodayTag(DateTime tag) {
  final now = DateTime.now();
  return tag.year == now.year && tag.month == now.month && tag.day == now.day;
}

/// "Today" or the localized date for a UTC-midnight date tag.
String dailyLogDayTitle(BuildContext context, DateTime tag) {
  if (isTodayTag(tag)) return AppLocalizations.of(context).logToday;
  return MaterialLocalizations.of(context)
      .formatMediumDate(DateTime(tag.year, tag.month, tag.day));
}

/// "7 soat 30 daqiqa", "2 soat" or "45 daqiqa".
String formatLogDuration(AppLocalizations l10n, int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return l10n.durationMinutesOnly(minutes);
  if (rest == 0) return l10n.durationHoursOnly(hours);
  return l10n.durationHoursMinutes(hours, rest);
}

/// Opens a daily log editor as a bottom sheet above the navigation bar.
Future<void> showDailyLogEditor(BuildContext context, Widget editor) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => editor,
  );
}

/// Asks before deleting a day's entry. Returns whether to delete.
Future<bool> confirmDailyLogDelete(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.logDeleteConfirmTitle),
      content: Text(l10n.logDeleteConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.logCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.logDelete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Title, fields, an optional error line and the save/delete buttons of a
/// daily log editor sheet. A null [onSave] disables saving.
class DailyLogEditorFrame extends StatelessWidget {
  const DailyLogEditorFrame({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.onDelete,
    this.error,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KunimSpacing.lg,
          0,
          KunimSpacing.lg,
          KunimSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: KunimSpacing.lg),
            ...children,
            if (error != null) ...[
              const SizedBox(height: KunimSpacing.md),
              Text(
                error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: KunimSpacing.lg),
            OverflowBar(
              alignment: onDelete == null
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: KunimSpacing.sm,
              overflowSpacing: KunimSpacing.sm,
              children: [
                if (onDelete != null)
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(l10n.logDelete),
                  ),
                FilledButton(onPressed: onSave, child: Text(l10n.logSave)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled group of fields inside an editor.
class DailyLogSection extends StatelessWidget {
  const DailyLogSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KunimSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: KunimSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// The optional note every daily log has, capped at the server limit.
class DailyLogNoteField extends StatelessWidget {
  const DailyLogNoteField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: controller,
      minLines: 2,
      maxLines: 4,
      maxLength: dailyLogMaxNoteLength,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: l10n.logNote,
        hintText: l10n.logNoteHint,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
    );
  }
}
