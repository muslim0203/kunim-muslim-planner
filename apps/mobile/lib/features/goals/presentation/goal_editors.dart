/// Editor sheets for goals and milestones, plus the small labels the goals
/// list and the goal detail screen share.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/db/app_database.dart';
import '../../../shared/widgets/daily_log_screen.dart';
import '../application/goals_providers.dart';

const int goalMaxTitleLength = 200;
const int goalMaxDescriptionLength = 1000;

/// "12 kun qoldi", "Muddat — bugun", "Muddati o‘tgan" or "Muddat belgilanmagan".
String goalDeadlineLabel(AppLocalizations l10n, int? daysRemaining) {
  if (daysRemaining == null) return l10n.goalNoTargetDate;
  if (daysRemaining < 0) return l10n.goalOverdue;
  if (daysRemaining == 0) return l10n.goalDueToday;
  return l10n.goalDaysRemaining(daysRemaining);
}

/// A target date as stored (a UTC-midnight date tag), formatted as that
/// calendar day.
String formatGoalDate(BuildContext context, DateTime tag) {
  return MaterialLocalizations.of(context)
      .formatMediumDate(DateTime(tag.year, tag.month, tag.day));
}

/// An icon and a short line of meta text (deadline, milestone count, ...).
class GoalMetaLabel extends StatelessWidget {
  const GoalMetaLabel({
    super.key,
    required this.icon,
    required this.text,
    this.color,
  });

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = this.color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: KunimSpacing.xs),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class GoalProgressBar extends StatelessWidget {
  const GoalProgressBar({super.key, required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(KunimRadii.small),
      child: LinearProgressIndicator(
        value: percent.clamp(0, 100) / 100,
        minHeight: 8,
        color: KunimModuleColors.mood,
        backgroundColor: KunimModuleColors.mood.withValues(alpha: 0.15),
      ),
    );
  }
}

/// Creates a goal, or edits [goal] when given.
Future<void> showGoalEditor(
  BuildContext context, {
  Goal? goal,
  VoidCallback? onDeleted,
}) {
  return showDailyLogEditor(
    context,
    GoalEditor(goal: goal, onDeleted: onDeleted),
  );
}

class GoalEditor extends ConsumerStatefulWidget {
  const GoalEditor({super.key, this.goal, this.onDeleted});

  final Goal? goal;

  /// Called after the goal was deleted and the sheet has closed.
  final VoidCallback? onDeleted;

  @override
  ConsumerState<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends ConsumerState<GoalEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.goal?.title ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.goal?.description ?? '');
  late DateTime? _targetDate = widget.goal?.targetDate;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onTitleChanged);
  }

  void _onTitleChanged() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editing = widget.goal != null;
    return DailyLogEditorFrame(
      title: editing ? l10n.goalEdit : l10n.goalNew,
      error: _error,
      onSave: _busy || _title.text.trim().isEmpty ? null : _save,
      onDelete: editing && !_busy ? _delete : null,
      children: [
        TextField(
          controller: _title,
          autofocus: !editing,
          maxLength: goalMaxTitleLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.goalTitleLabel,
            counterText: '',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: KunimSpacing.md),
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 4,
          maxLength: goalMaxDescriptionLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.goalDescriptionLabel,
            hintText: l10n.logNoteHint,
            counterText: '',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: KunimSpacing.lg),
        DailyLogSection(
          title: l10n.goalTargetDateLabel,
          child: GoalDateField(
            value: _targetDate,
            onChanged: (value) => setState(() => _targetDate = value),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final controller = ref.read(goalsControllerProvider.notifier);
    final title = _title.text.trim();
    final description = _description.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });

    final goal = widget.goal;
    if (goal == null) {
      await controller.createGoal(
        title: title,
        description: description.isEmpty ? null : description,
        targetDate: _targetDate,
      );
    } else {
      await controller.updateGoal(
        id: goal.id,
        title: title,
        description: Value(description.isEmpty ? null : description),
        targetDate: _targetDate,
        clearTargetDate: _targetDate == null,
      );
    }

    if (!mounted) return;
    if (ref.read(goalsControllerProvider).hasError) {
      setState(() {
        _busy = false;
        _error = l10n.logSaveFailed;
      });
      return;
    }
    navigator.pop();
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    if (!await confirmGoalDelete(context) || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await ref
        .read(goalsControllerProvider.notifier)
        .deleteGoalWithMilestones(widget.goal!.id);
    if (!mounted) return;
    if (ref.read(goalsControllerProvider).hasError) {
      setState(() {
        _busy = false;
        _error = l10n.errorGeneric;
      });
      return;
    }
    navigator.pop();
    widget.onDeleted?.call();
  }
}

/// Asks before deleting a goal together with its milestones.
Future<bool> confirmGoalDelete(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.goalDeleteConfirmTitle),
      content: Text(l10n.goalDeleteConfirmBody),
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

/// Picks a target date (stored as a UTC-midnight date tag, the same shape
/// pulled `target_date` values have) or clears it.
class GoalDateField extends StatelessWidget {
  const GoalDateField(
      {super.key, required this.value, required this.onChanged});

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = this.value;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pick(context),
            icon: const Icon(Icons.event_outlined),
            label: Text(
              value == null
                  ? l10n.goalNoTargetDate
                  : formatGoalDate(context, value),
            ),
          ),
        ),
        if (value != null)
          IconButton(
            tooltip: l10n.goalClearDate,
            icon: const Icon(Icons.clear_rounded),
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final first = DateTime(now.year - 5);
    final last = DateTime(now.year + 20);
    final current = value;
    var initial = current == null
        ? DateTime(now.year, now.month, now.day)
        : DateTime(current.year, current.month, current.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      onChanged(DateTime.utc(picked.year, picked.month, picked.day));
    }
  }
}

/// Adds a milestone to [goalId], or edits [milestone] when given.
Future<void> showMilestoneEditor(
  BuildContext context, {
  required String goalId,
  Milestone? milestone,
  int sortOrder = 0,
}) {
  return showDailyLogEditor(
    context,
    MilestoneEditor(goalId: goalId, milestone: milestone, sortOrder: sortOrder),
  );
}

class MilestoneEditor extends ConsumerStatefulWidget {
  const MilestoneEditor({
    super.key,
    required this.goalId,
    this.milestone,
    this.sortOrder = 0,
  });

  final String goalId;
  final Milestone? milestone;

  /// Position of a new milestone; ignored when editing.
  final int sortOrder;

  @override
  ConsumerState<MilestoneEditor> createState() => _MilestoneEditorState();
}

class _MilestoneEditorState extends ConsumerState<MilestoneEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.milestone?.title ?? '');
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onTitleChanged);
  }

  void _onTitleChanged() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editing = widget.milestone != null;
    return DailyLogEditorFrame(
      title: editing ? l10n.goalMilestoneEdit : l10n.goalAddMilestone,
      error: _error,
      onSave: _busy || _title.text.trim().isEmpty ? null : _save,
      onDelete: editing && !_busy ? _delete : null,
      children: [
        TextField(
          controller: _title,
          autofocus: !editing,
          maxLength: goalMaxTitleLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.goalTitleLabel,
            counterText: '',
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final milestone = widget.milestone;
    final controller = ref.read(goalsControllerProvider.notifier);
    await _run(
      () => milestone == null
          ? controller.addMilestone(
              goalId: widget.goalId,
              title: title,
              sortOrder: widget.sortOrder,
            )
          : controller.updateMilestone(id: milestone.id, title: title),
      failure: AppLocalizations.of(context).logSaveFailed,
    );
  }

  Future<void> _delete() {
    return _run(
      () => ref
          .read(goalsControllerProvider.notifier)
          .deleteMilestone(widget.milestone!.id),
      failure: AppLocalizations.of(context).errorGeneric,
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String failure,
  }) async {
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    await action();
    if (!mounted) return;
    if (ref.read(goalsControllerProvider).hasError) {
      setState(() {
        _busy = false;
        _error = failure;
      });
      return;
    }
    navigator.pop();
  }
}
