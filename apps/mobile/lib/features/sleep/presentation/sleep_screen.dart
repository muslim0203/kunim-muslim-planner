/// "Uyqu": last night's bedtime, wake-up time and quality, filed under the
/// day the user woke up. The duration is always derived from the two times.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/db/app_database.dart';
import '../../../shared/widgets/daily_log_screen.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../../habits/domain/local_day.dart';
import '../application/sleep_providers.dart';
import '../domain/sleep_limits.dart';

class SleepScreen extends ConsumerWidget {
  const SleepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return DailyLogScreen<SleepLog>(
      title: l10n.moduleSleep,
      intro: l10n.sleepIntro,
      today: ref.watch(todaySleepLogProvider),
      recent: ref.watch(recentSleepLogsProvider),
      dateOf: (entry) => entry.date,
      summaryOf: (context, entry) => _SleepSummary(entry: entry),
      onEdit: (entry) => showDailyLogEditor(
        context,
        SleepEditor(
          day: entry == null
              ? LocalDay.now()
              : LocalDay.fromUtcMidnight(entry.date),
          entry: entry,
        ),
      ),
    );
  }
}

abstract final class SleepLabels {
  static String quality(AppLocalizations l10n, int quality) {
    return switch (quality) {
      1 => l10n.sleepQuality1,
      2 => l10n.sleepQuality2,
      3 => l10n.sleepQuality3,
      4 => l10n.sleepQuality4,
      _ => l10n.sleepQuality5,
    };
  }

  static String time(BuildContext context, TimeOfDay time) {
    return MaterialLocalizations.of(context)
        .formatTimeOfDay(time, alwaysUse24HourFormat: true);
  }
}

class _SleepSummary extends StatelessWidget {
  const _SleepSummary({required this.entry});

  final SleepLog entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bed = TimeOfDay.fromDateTime(entry.bedTime.toLocal());
    final wake = TimeOfDay.fromDateTime(entry.wakeTime.toLocal());
    final quality = entry.quality;
    return Row(
      children: [
        const Icon(Icons.bedtime_outlined, color: KunimModuleColors.sleep),
        const SizedBox(width: KunimSpacing.sm),
        Expanded(
          child: Text(
            [
              formatLogDuration(l10n, entry.durationMin),
              '${SleepLabels.time(context, bed)} – '
                  '${SleepLabels.time(context, wake)}',
              if (quality != null) SleepLabels.quality(l10n, quality),
            ].join(' · '),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class SleepEditor extends ConsumerStatefulWidget {
  const SleepEditor({super.key, required this.day, this.entry});

  /// The day the user woke up.
  final LocalDay day;
  final SleepLog? entry;

  @override
  ConsumerState<SleepEditor> createState() => _SleepEditorState();
}

class _SleepEditorState extends ConsumerState<SleepEditor> {
  late TimeOfDay _bed;
  late TimeOfDay _wake;
  int? _quality;
  late final TextEditingController _note;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _bed = entry == null
        ? const TimeOfDay(hour: 23, minute: 0)
        : TimeOfDay.fromDateTime(entry.bedTime.toLocal());
    _wake = entry == null
        ? const TimeOfDay(hour: 7, minute: 0)
        : TimeOfDay.fromDateTime(entry.wakeTime.toLocal());
    _quality = entry?.quality;
    _note = TextEditingController(text: entry?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Bedtime and wake-up as local instants; bedtime moves to the previous
  /// evening when it is not before the wake-up time. `null` when both times
  /// are equal.
  (DateTime, DateTime)? get _night {
    if (_bed == _wake) return null;
    final day = widget.day;
    final wake =
        DateTime(day.year, day.month, day.day, _wake.hour, _wake.minute);
    var bed = DateTime(day.year, day.month, day.day, _bed.hour, _bed.minute);
    if (!bed.isBefore(wake)) bed = bed.subtract(const Duration(days: 1));
    return (bed, wake);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final night = _night;
    return DailyLogEditorFrame(
      title: dailyLogDayTitle(context, widget.day.toUtcMidnight()),
      error: night == null ? l10n.sleepInvalid : _error,
      onSave: night == null ? null : () => _save(night),
      onDelete: widget.entry == null ? null : _delete,
      children: [
        _TimeRow(
          icon: Icons.bedtime_outlined,
          label: l10n.sleepBedTime,
          time: _bed,
          onPicked: (time) => setState(() => _bed = time),
        ),
        const SizedBox(height: KunimSpacing.sm),
        _TimeRow(
          icon: Icons.wb_twilight_outlined,
          label: l10n.sleepWakeTime,
          time: _wake,
          onPicked: (time) => setState(() => _wake = time),
        ),
        const SizedBox(height: KunimSpacing.md),
        if (night != null)
          Text(
            '${l10n.sleepDuration}: '
            '${formatLogDuration(l10n, night.$2.difference(night.$1).inMinutes)}',
            style: theme.textTheme.titleSmall,
          ),
        const SizedBox(height: KunimSpacing.lg),
        DailyLogSection(
          title: l10n.sleepQuality,
          child: Wrap(
            spacing: KunimSpacing.sm,
            runSpacing: KunimSpacing.sm,
            children: [
              for (var quality = SleepLimits.minQuality;
                  quality <= SleepLimits.maxQuality;
                  quality++)
                ChoiceChip(
                  label: Text(SleepLabels.quality(l10n, quality)),
                  selected: _quality == quality,
                  onSelected: (selected) =>
                      setState(() => _quality = selected ? quality : null),
                ),
            ],
          ),
        ),
        DailyLogNoteField(controller: _note),
      ],
    );
  }

  Future<void> _save((DateTime, DateTime) night) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(sleepLogRepositoryProvider).saveForDay(
            widget.day,
            bedTime: night.$1,
            wakeTime: night.$2,
            quality: _quality,
            note: _note.text,
          );
      navigator.pop();
    } on ArgumentError {
      if (mounted) setState(() => _error = l10n.logSaveFailed);
    }
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    if (!await confirmDailyLogDelete(context)) return;
    await ref.read(sleepLogRepositoryProvider).deleteForDay(widget.day);
    navigator.pop();
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.icon,
    required this.label,
    required this.time,
    required this.onPicked,
  });

  final IconData icon;
  final String label;
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onPicked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HeritageCard(
      onTap: () async {
        final picked =
            await showTimePicker(context: context, initialTime: time);
        if (picked != null) onPicked(picked);
      },
      padding: const EdgeInsets.symmetric(
        horizontal: KunimSpacing.lg,
        vertical: KunimSpacing.md,
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: KunimSpacing.md),
          Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
          const SizedBox(width: KunimSpacing.sm),
          Text(
            SleepLabels.time(context, time),
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
