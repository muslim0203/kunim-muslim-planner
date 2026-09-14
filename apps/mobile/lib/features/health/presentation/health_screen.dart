/// "Sog'liq": the day's water, steps, exercise, calories and weight. These
/// are personal records only; the screen says plainly that they are not
/// medical advice and never interprets the numbers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/db/app_database.dart';
import '../../../shared/widgets/daily_log_screen.dart';
import '../../habits/domain/local_day.dart';
import '../application/health_providers.dart';
import '../domain/health_limits.dart';

class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return DailyLogScreen<HealthLog>(
      title: l10n.moduleHealth,
      intro: l10n.healthIntro,
      footer: l10n.healthDisclaimer,
      today: ref.watch(todayHealthLogProvider),
      recent: ref.watch(recentHealthLogsProvider),
      dateOf: (entry) => entry.date,
      summaryOf: (context, entry) => _HealthSummary(entry: entry),
      onEdit: (entry) => showDailyLogEditor(
        context,
        HealthEditor(
          day: entry == null
              ? LocalDay.now()
              : LocalDay.fromUtcMidnight(entry.date),
          entry: entry,
        ),
      ),
    );
  }
}

/// `72.5`, and `70` rather than `70.0`.
String formatWeightKg(double kg) {
  final text = kg.toString();
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

class _HealthSummary extends StatelessWidget {
  const _HealthSummary({required this.entry});

  final HealthLog entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parts = [
      if (entry.waterMl != null) l10n.healthWaterValue(entry.waterMl!),
      if (entry.steps != null) l10n.healthStepsValue(entry.steps!),
      if (entry.workoutMin != null) l10n.healthWorkoutValue(entry.workoutMin!),
      if (entry.calories != null) l10n.healthCaloriesValue(entry.calories!),
      if (entry.weightKg != null)
        l10n.healthWeightValue(formatWeightKg(entry.weightKg!)),
    ];
    return Row(
      children: [
        const Icon(Icons.favorite_border_rounded,
            color: KunimModuleColors.health),
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

class HealthEditor extends ConsumerStatefulWidget {
  const HealthEditor({super.key, required this.day, this.entry});

  final LocalDay day;
  final HealthLog? entry;

  @override
  ConsumerState<HealthEditor> createState() => _HealthEditorState();
}

class _HealthEditorState extends ConsumerState<HealthEditor> {
  late final TextEditingController _water;
  late final TextEditingController _steps;
  late final TextEditingController _workout;
  late final TextEditingController _calories;
  late final TextEditingController _weight;
  late final TextEditingController _note;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _water = TextEditingController(text: entry?.waterMl?.toString() ?? '');
    _steps = TextEditingController(text: entry?.steps?.toString() ?? '');
    _workout = TextEditingController(text: entry?.workoutMin?.toString() ?? '');
    _calories = TextEditingController(text: entry?.calories?.toString() ?? '');
    _weight = TextEditingController(
      text: entry?.weightKg == null ? '' : formatWeightKg(entry!.weightKg!),
    );
    _note = TextEditingController(text: entry?.note ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _water,
      _steps,
      _workout,
      _calories,
      _weight,
      _note,
    ]) {
      controller.dispose();
    }
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
        _NumberField(
          controller: _water,
          label: l10n.healthWater,
          icon: Icons.water_drop_outlined,
        ),
        _NumberField(
          controller: _steps,
          label: l10n.healthSteps,
          icon: Icons.directions_walk_rounded,
        ),
        _NumberField(
          controller: _workout,
          label: l10n.healthWorkout,
          icon: Icons.fitness_center_rounded,
        ),
        _NumberField(
          controller: _calories,
          label: l10n.healthCalories,
          icon: Icons.local_fire_department_outlined,
        ),
        _NumberField(
          controller: _weight,
          label: l10n.healthWeight,
          icon: Icons.monitor_weight_outlined,
          decimal: true,
        ),
        DailyLogNoteField(controller: _note),
      ],
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final int? water;
    final int? steps;
    final int? workout;
    final int? calories;
    final double? weight;
    try {
      water = _int(_water, HealthLimits.maxWaterMl);
      steps = _int(_steps, HealthLimits.maxSteps);
      workout = _int(_workout, HealthLimits.maxWorkoutMin);
      calories = _int(_calories, HealthLimits.maxCalories);
      weight = _weightKg();
    } on FormatException {
      setState(() => _error = l10n.logValueInvalid);
      return;
    }
    if (water == null &&
        steps == null &&
        workout == null &&
        calories == null &&
        weight == null &&
        _note.text.trim().isEmpty) {
      setState(() => _error = l10n.healthNeedValue);
      return;
    }
    try {
      await ref.read(healthLogRepositoryProvider).saveForDay(
            widget.day,
            waterMl: water,
            steps: steps,
            workoutMin: workout,
            calories: calories,
            weightKg: weight,
            note: _note.text,
          );
      navigator.pop();
    } on ArgumentError {
      if (mounted) setState(() => _error = l10n.logSaveFailed);
    }
  }

  static int? _int(TextEditingController controller, int max) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null || value < 0 || value > max) {
      throw const FormatException();
    }
    return value;
  }

  double? _weightKg() {
    final text = _weight.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null ||
        value < HealthLimits.minWeightKg ||
        value > HealthLimits.maxWeightKg) {
      throw const FormatException();
    }
    return value;
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    if (!await confirmDailyLogDelete(context)) return;
    await ref.read(healthLogRepositoryProvider).deleteForDay(widget.day);
    navigator.pop();
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.icon,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KunimSpacing.md),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
          ),
        ],
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
