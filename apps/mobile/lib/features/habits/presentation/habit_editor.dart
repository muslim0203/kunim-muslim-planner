/// The habit editor sheet, the one-tap "today" action, and the labels the
/// habits screen and the home tab share.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/db/app_database.dart';
import '../../../shared/widgets/daily_log_screen.dart';
import '../application/habit_mutation_controller.dart';
import '../application/habit_totals_provider.dart';
import '../application/habits_today_provider.dart';
import '../domain/habit_kind.dart';
import '../domain/habit_progress.dart';
import '../domain/habit_schedule.dart';
import '../domain/streak.dart';
import 'habit_kind_labels.dart';

const int habitMaxTitleLength = 200;
const int habitMaxTargetCount = 99;

/// Today's one-tap action: adds one to today's count until the target is
/// reached; on a habit already done today it clears today's check-in.
Future<void> toggleHabitToday(WidgetRef ref, HabitToday habit) {
  final controller = ref.read(habitMutationControllerProvider.notifier);
  if (habit.isDone) {
    return controller.removeLog(habitId: habit.habit.id, day: habit.day);
  }
  return controller.adjustCount(habitId: habit.habit.id, day: habit.day);
}

String habitWeekdayShort(AppLocalizations l10n, int weekday) {
  return switch (weekday) {
    DateTime.monday => l10n.calWeekdayMondayShort,
    DateTime.tuesday => l10n.calWeekdayTuesdayShort,
    DateTime.wednesday => l10n.calWeekdayWednesdayShort,
    DateTime.thursday => l10n.calWeekdayThursdayShort,
    DateTime.friday => l10n.calWeekdayFridayShort,
    DateTime.saturday => l10n.calWeekdaySaturdayShort,
    _ => l10n.calWeekdaySundayShort,
  };
}

/// "Har kuni", "Dush, Chor, Jum" or "Haftasiga 3 marta".
String habitScheduleLabel(AppLocalizations l10n, HabitSchedule schedule) {
  return switch (schedule.type) {
    HabitScheduleType.everyDay => l10n.habitScheduleEveryDay,
    HabitScheduleType.specificWeekdays => (schedule.weekdays.toList()..sort())
        .map((day) => habitWeekdayShort(l10n, day))
        .join(', '),
    HabitScheduleType.timesPerWeek =>
      l10n.habitScheduleTimesPerWeek(schedule.timesPerWeek),
  };
}

/// "Ketma-ketlik: 5 kun" (or weeks for a times-per-week habit).
String habitStreakLabel(AppLocalizations l10n, StreakResult streak) {
  return switch (streak.unit) {
    StreakUnit.day => l10n.habitStreakDays(streak.current),
    StreakUnit.week => l10n.habitStreakWeeks(streak.current),
  };
}

/// Creates a habit, or edits [habit] when given.
Future<void> showHabitEditor(BuildContext context, {Habit? habit}) {
  return showDailyLogEditor(context, HabitEditor(habit: habit));
}

class HabitEditor extends ConsumerStatefulWidget {
  const HabitEditor({super.key, this.habit});

  final Habit? habit;

  @override
  ConsumerState<HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends ConsumerState<HabitEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.habit?.title ?? '');
  late HabitScheduleType _type;
  late Set<int> _weekdays;
  late int _timesPerWeek;
  late int _target;
  late HabitKind _kind;
  late final TextEditingController _total;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final habit = widget.habit;
    final schedule = habit == null
        ? HabitSchedule.defaultSchedule
        : HabitSchedule.fromJson(habit.frequency);
    _type = schedule.type;
    _weekdays = {...schedule.weekdays};
    _timesPerWeek = schedule.type == HabitScheduleType.timesPerWeek
        ? schedule.timesPerWeek
        : 3;
    _target = (habit?.targetCount ?? 1).clamp(1, habitMaxTargetCount);
    _kind = HabitKind.fromCode(habit?.kind);
    _total = TextEditingController(
      text: habit?.totalTarget?.toString() ?? '',
    );
    _total.addListener(_onTitleChanged);
    _title.addListener(_onTitleChanged);
  }

  void _onTitleChanged() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _total.dispose();
    super.dispose();
  }

  /// The total this widget works towards, or null when it is open-ended
  /// or the field is empty.
  int? get _totalTarget {
    if (!_kind.hasTotal) return null;
    final value = int.tryParse(_total.text.trim());
    return value == null || value < 1 ? null : value;
  }

  HabitSchedule get _schedule => switch (_type) {
        HabitScheduleType.everyDay => const HabitSchedule.everyDay(),
        HabitScheduleType.specificWeekdays =>
          HabitSchedule.specificWeekdays({..._weekdays}),
        HabitScheduleType.timesPerWeek =>
          HabitSchedule.timesPerWeek(_timesPerWeek),
      };

  bool get _missingWeekdays =>
      _type == HabitScheduleType.specificWeekdays && _weekdays.isEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final editing = widget.habit != null;

    return DailyLogEditorFrame(
      title: editing ? l10n.habitEdit : l10n.habitNew,
      error: _error,
      onSave: _busy || _title.text.trim().isEmpty || _missingWeekdays
          ? null
          : _save,
      onDelete: editing && !_busy ? _archive : null,
      children: [
        TextField(
          controller: _title,
          autofocus: !editing,
          maxLength: habitMaxTitleLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.habitNameLabel,
            counterText: '',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: KunimSpacing.lg),
        DailyLogSection(
          title: l10n.habitWidgetType,
          child: Wrap(
            spacing: KunimSpacing.sm,
            runSpacing: KunimSpacing.sm,
            children: [
              for (final kind in HabitKind.values)
                ChoiceChip(
                  avatar: Icon(habitKindIcon(kind), size: 18),
                  label: Text(habitKindName(l10n, kind)),
                  selected: _kind == kind,
                  onSelected: (_) => setState(() {
                    _kind = kind;
                    // A fresh widget starts from its kind's own daily
                    // amount; an edit keeps what the user already set.
                    if (!editing) _target = kind.dailyTarget;
                  }),
                ),
            ],
          ),
        ),
        DailyLogSection(
          title: l10n.habitScheduleLabel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: KunimSpacing.sm,
                runSpacing: KunimSpacing.sm,
                children: [
                  for (final type in HabitScheduleType.values)
                    ChoiceChip(
                      label: Text(switch (type) {
                        HabitScheduleType.everyDay =>
                          l10n.habitScheduleEveryDay,
                        HabitScheduleType.specificWeekdays =>
                          l10n.habitScheduleSpecificWeekdays,
                        HabitScheduleType.timesPerWeek =>
                          l10n.habitScheduleTimesPerWeek(_timesPerWeek),
                      }),
                      selected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                    ),
                ],
              ),
              if (_type == HabitScheduleType.specificWeekdays) ...[
                const SizedBox(height: KunimSpacing.md),
                Wrap(
                  spacing: KunimSpacing.xs,
                  runSpacing: KunimSpacing.xs,
                  children: [
                    for (var day = DateTime.monday;
                        day <= DateTime.sunday;
                        day++)
                      FilterChip(
                        label: Text(habitWeekdayShort(l10n, day)),
                        selected: _weekdays.contains(day),
                        onSelected: (on) => setState(() {
                          if (on) {
                            _weekdays.add(day);
                          } else {
                            _weekdays.remove(day);
                          }
                        }),
                      ),
                  ],
                ),
                if (_missingWeekdays)
                  Padding(
                    padding: const EdgeInsets.only(top: KunimSpacing.xs),
                    child: Text(
                      l10n.habitWeekdaysRequired,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
              if (_type == HabitScheduleType.timesPerWeek) ...[
                const SizedBox(height: KunimSpacing.sm),
                HabitStepper(
                  label: l10n.habitScheduleTimesPerWeek(_timesPerWeek),
                  value: _timesPerWeek,
                  min: 1,
                  max: 7,
                  onChanged: (value) => setState(() => _timesPerWeek = value),
                ),
              ],
            ],
          ),
        ),
        DailyLogSection(
          title: l10n.habitDailyLabel,
          child: HabitStepper(
            label: habitAmount(l10n, _kind, _target),
            value: _target,
            min: 1,
            max: habitMaxTargetCount,
            onChanged: (value) => setState(() => _target = value),
          ),
        ),
        if (_kind.hasTotal)
          DailyLogSection(
            title: l10n.habitTotalLabel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _total,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: l10n.habitTotalHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_finishInDays case final days?) ...[
                  const SizedBox(height: KunimSpacing.xs),
                  Text(
                    l10n.habitFinishInDays(days),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// How long the widget would take from where it stands now, or null
  /// when there is no usable total yet.
  int? get _finishInDays {
    final total = _totalTarget;
    if (total == null) return null;
    final done = widget.habit == null
        ? 0
        : ref.watch(habitTotalsProvider)[widget.habit!.id] ?? 0;
    return HabitProgress(done: done, total: total, perDay: _target).daysLeft;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final controller = ref.read(habitMutationControllerProvider.notifier);
    final title = _title.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });

    final habit = widget.habit;
    if (habit == null) {
      await controller.createHabit(
        title: title,
        schedule: _schedule,
        targetCount: _target,
        kind: _kind,
        totalTarget: _totalTarget,
      );
    } else {
      await controller.updateHabit(
        id: habit.id,
        title: title,
        schedule: _schedule,
        targetCount: _target,
        kind: _kind,
        totalTarget: () => _totalTarget,
      );
    }

    if (!mounted) return;
    if (ref.read(habitMutationControllerProvider).hasError) {
      setState(() {
        _busy = false;
        _error = l10n.logSaveFailed;
      });
      return;
    }
    navigator.pop();
  }

  Future<void> _archive() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.habitArchiveConfirmTitle),
        content: Text(l10n.habitArchiveConfirmBody),
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
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    await ref
        .read(habitMutationControllerProvider.notifier)
        .archiveHabit(widget.habit!.id);
    if (!mounted) return;
    if (ref.read(habitMutationControllerProvider).hasError) {
      setState(() {
        _busy = false;
        _error = l10n.errorGeneric;
      });
      return;
    }
    navigator.pop();
  }
}

/// A number with minus/plus buttons, e.g. "Kuniga 3 marta".
class HabitStepper extends StatelessWidget {
  const HabitStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        IconButton.outlined(
          tooltip: l10n.habitDecrease,
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        IconButton.outlined(
          tooltip: l10n.habitIncrease,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}
