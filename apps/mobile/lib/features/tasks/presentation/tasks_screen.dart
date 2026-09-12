/// The "Kun tartibi" tab: the full task list, with completion, Top-3
/// pinning, and a sheet for creating or editing a task.
///
/// Reads providers and renders. No database access, no merge logic, and
/// every user-visible string comes from the ARB files.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tasks_table.dart' show TaskPriority;
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/kunim_card.dart';
import '../application/task_mutation_controller.dart';
import '../application/task_providers.dart';
import '../application/top_three_mutation_controller.dart';
import '../application/top_three_providers.dart';
import '../domain/task_status.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.watch(allTasksProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.taskScreenTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTaskEditor(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.taskNew),
      ),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => EmptyState(message: l10n.errorGeneric),
        data: (items) {
          final open = items.where((t) => !t.isCompleted).toList();
          if (items.isEmpty) {
            return EmptyState(
              message: l10n.taskEmptyState,
              icon: Icons.checklist_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              KunimSpacing.lg,
              KunimSpacing.lg,
              KunimSpacing.lg,
              // Clear the FAB so the last card is never covered.
              KunimSpacing.xxl * 2,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: KunimSpacing.md),
                child: Text(
                  l10n.taskLeftCount(open.length),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final task in items) _TaskRow(task: task),
            ],
          );
        },
      ),
    );
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final done = task.isCompleted;
    final pinned = ref.watch(topThreeSelectionProvider).maybeWhen(
          data: (selection) => selection.taskIds.contains(task.id),
          orElse: () => false,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: KunimSpacing.sm),
      child: KunimCard(
        accentColor: _priorityColor(task.priority),
        onTap: () => showTaskEditor(context, task: task),
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
                  // ADR-0002 rule 8: completed_at is max-wins server-side,
                  // so un-completing can lose to a later completion from
                  // another device. Deliberate, not a bug.
                  if (done) {
                    controller.uncompleteTask(task.id);
                  } else {
                    controller.completeTask(task.id);
                  }
                },
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: done
                        ? TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: theme.disabledColor,
                          )
                        : null,
                  ),
                  if (task.isOverdue())
                    Text(
                      l10n.taskOverdue,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            Semantics(
              label: l10n.homeTopThree,
              button: true,
              child: IconButton(
                icon: Icon(pinned ? Icons.star : Icons.star_outline),
                color: pinned ? KunimModuleColors.work : null,
                onPressed: () {
                  final controller = ref.read(
                    topThreeMutationControllerProvider.notifier,
                  );
                  if (pinned) {
                    controller.unpin(task.id);
                  } else {
                    controller.pin(task.id);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color? _priorityColor(TaskPriority priority) => switch (priority) {
        TaskPriority.high => KunimModuleColors.family,
        TaskPriority.medium => KunimModuleColors.work,
        TaskPriority.low => null,
      };
}

/// Opens the create/edit sheet. Passing [task] edits it, omitting it
/// creates a new one.
Future<void> showTaskEditor(BuildContext context, {Task? task}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _TaskEditorSheet(task: task),
    ),
  );
}

class _TaskEditorSheet extends ConsumerStatefulWidget {
  const _TaskEditorSheet({this.task});

  final Task? task;

  @override
  ConsumerState<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<_TaskEditorSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.task?.title ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.task?.description ?? '',
  );
  late TaskPriority _priority = widget.task?.priority ?? TaskPriority.medium;
  late DateTime? _dueDate = widget.task?.dueDate;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.task != null;

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final notes = _notes.text.trim();
    final controller = ref.read(taskMutationControllerProvider.notifier);

    if (_isEditing) {
      await controller.updateTask(
        widget.task!.id,
        title: title,
        description: Value(notes.isEmpty ? null : notes),
        priority: _priority,
        dueDate: Value(_dueDate),
      );
    } else {
      await controller.createTask(
        title: title,
        description: notes.isEmpty ? null : notes,
        priority: _priority,
        dueDate: _dueDate,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.taskDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(taskMutationControllerProvider.notifier)
        .deleteTask(widget.task!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(KunimSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? l10n.taskScreenTitle : l10n.taskNew,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: KunimSpacing.lg),
            TextField(
              controller: _title,
              autofocus: !_isEditing,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: l10n.taskTitleLabel),
            ),
            const SizedBox(height: KunimSpacing.md),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(labelText: l10n.taskNotesLabel),
            ),
            const SizedBox(height: KunimSpacing.md),
            _PrioritySelector(
              value: _priority,
              onChanged: (value) => setState(() => _priority = value),
            ),
            const SizedBox(height: KunimSpacing.md),
            _DueDateField(
              value: _dueDate,
              onChanged: (value) => setState(() => _dueDate = value),
            ),
            const SizedBox(height: KunimSpacing.xl),
            Row(
              children: [
                if (_isEditing)
                  TextButton(
                    onPressed: _confirmDelete,
                    child: Text(l10n.actionDelete),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.actionCancel),
                ),
                const SizedBox(width: KunimSpacing.sm),
                FilledButton(
                  onPressed: _save,
                  child: Text(l10n.actionSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrioritySelector extends StatelessWidget {
  const _PrioritySelector({required this.value, required this.onChanged});

  final TaskPriority value;
  final ValueChanged<TaskPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = <TaskPriority, String>{
      TaskPriority.low: l10n.taskPriorityLow,
      TaskPriority.medium: l10n.taskPriorityMedium,
      TaskPriority.high: l10n.taskPriorityHigh,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.taskPriorityLabel),
        const SizedBox(height: KunimSpacing.sm),
        SegmentedButton<TaskPriority>(
          segments: [
            for (final entry in labels.entries)
              ButtonSegment(value: entry.key, label: Text(entry.value)),
          ],
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}

class _DueDateField extends StatelessWidget {
  const _DueDateField({required this.value, required this.onChanged});

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localizations = MaterialLocalizations.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            value == null
                ? l10n.taskDueDateLabel
                : localizations.formatMediumDate(value!),
          ),
        ),
        if (value != null)
          IconButton(
            tooltip: l10n.actionDelete,
            icon: const Icon(Icons.clear),
            onPressed: () => onChanged(null),
          ),
        IconButton(
          tooltip: l10n.taskDueDateLabel,
          icon: const Icon(Icons.calendar_today_outlined),
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 5),
            );
            if (picked != null) onChanged(picked);
          },
        ),
      ],
    );
  }
}
