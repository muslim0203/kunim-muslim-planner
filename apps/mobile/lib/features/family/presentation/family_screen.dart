/// "Oila": time spent with family each day and what it was spent on.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/db/app_database.dart';
import '../../../shared/widgets/daily_log_screen.dart';
import '../../habits/domain/local_day.dart';
import '../application/family_providers.dart';
import '../data/family_log_repository.dart';
import '../domain/family_options.dart';

class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return DailyLogScreen<FamilyLog>(
      title: l10n.moduleFamily,
      intro: l10n.familyIntro,
      today: ref.watch(todayFamilyLogProvider),
      recent: ref.watch(recentFamilyLogsProvider),
      dateOf: (entry) => entry.date,
      summaryOf: (context, entry) => _FamilySummary(entry: entry),
      onEdit: (entry) => showDailyLogEditor(
        context,
        FamilyEditor(
          day: entry == null
              ? LocalDay.now()
              : LocalDay.fromUtcMidnight(entry.date),
          entry: entry,
        ),
      ),
    );
  }
}

abstract final class FamilyLabels {
  /// Unknown codes (from a newer app version) show as the code itself.
  static String activity(AppLocalizations l10n, String code) {
    return switch (code) {
      'talk' => l10n.familyActivityTalk,
      'meal' => l10n.familyActivityMeal,
      'walk' => l10n.familyActivityWalk,
      'call' => l10n.familyActivityCall,
      'help' => l10n.familyActivityHelp,
      'visit' => l10n.familyActivityVisit,
      'play' => l10n.familyActivityPlay,
      'reading' => l10n.familyActivityReading,
      _ => code,
    };
  }
}

class _FamilySummary extends StatelessWidget {
  const _FamilySummary({required this.entry});

  final FamilyLog entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activities = FamilyLogRepository.activitiesOf(entry)
        .map((code) => FamilyLabels.activity(l10n, code))
        .join(', ');
    final parts = [
      if (entry.minutes != null) formatLogDuration(l10n, entry.minutes!),
      if (activities.isNotEmpty) activities,
    ];
    return Row(
      children: [
        const Icon(Icons.favorite_outline_rounded,
            color: KunimModuleColors.family),
        const SizedBox(width: KunimSpacing.sm),
        Expanded(
          child: Text(
            parts.isEmpty ? (entry.note ?? '') : parts.join(' · '),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class FamilyEditor extends ConsumerStatefulWidget {
  const FamilyEditor({super.key, required this.day, this.entry});

  final LocalDay day;
  final FamilyLog? entry;

  @override
  ConsumerState<FamilyEditor> createState() => _FamilyEditorState();
}

class _FamilyEditorState extends ConsumerState<FamilyEditor> {
  static const List<int> _quickMinutes = [15, 30, 60, 120];

  late final TextEditingController _minutes;
  late final Set<String> _activities;
  late final TextEditingController _note;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _minutes = TextEditingController(text: entry?.minutes?.toString() ?? '');
    _activities = entry == null
        ? <String>{}
        : FamilyLogRepository.activitiesOf(entry).toSet();
    _note = TextEditingController(text: entry?.note ?? '');
  }

  @override
  void dispose() {
    _minutes.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DailyLogEditorFrame(
      title: dailyLogDayTitle(context, widget.day.toUtcMidnight()),
      error: _error,
      onSave: _save,
      onDelete: widget.entry == null ? null : _delete,
      children: [
        DailyLogSection(
          title: l10n.familyMinutes,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: l10n.familyMinutes,
                  prefixIcon: const Icon(Icons.schedule_rounded),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: KunimSpacing.sm),
              Wrap(
                spacing: KunimSpacing.sm,
                runSpacing: KunimSpacing.sm,
                children: [
                  for (final minutes in _quickMinutes)
                    ActionChip(
                      label: Text(formatLogDuration(l10n, minutes)),
                      onPressed: () => setState(
                        () => _minutes.text = minutes.toString(),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        DailyLogSection(
          title: l10n.familyActivities,
          child: Wrap(
            spacing: KunimSpacing.sm,
            runSpacing: KunimSpacing.sm,
            children: [
              for (final code in {...FamilyOptions.activities, ..._activities})
                FilterChip(
                  label: Text(FamilyLabels.activity(l10n, code)),
                  selected: _activities.contains(code),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _activities.add(code);
                    } else {
                      _activities.remove(code);
                    }
                  }),
                ),
            ],
          ),
        ),
        DailyLogNoteField(controller: _note),
      ],
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final text = _minutes.text.trim();
    final minutes = text.isEmpty ? null : int.tryParse(text);
    if (text.isNotEmpty &&
        (minutes == null || minutes > FamilyOptions.maxMinutes)) {
      setState(() => _error = l10n.logValueInvalid);
      return;
    }
    if (minutes == null && _activities.isEmpty && _note.text.trim().isEmpty) {
      setState(() => _error = l10n.familyNeedValue);
      return;
    }
    try {
      await ref.read(familyLogRepositoryProvider).saveForDay(
            widget.day,
            minutes: minutes,
            activities: _activities,
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
    await ref.read(familyLogRepositoryProvider).deleteForDay(widget.day);
    navigator.pop();
  }
}
