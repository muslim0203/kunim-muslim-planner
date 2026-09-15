/// The prayer module: today's times for the chosen city, the next prayer,
/// marks for the prayers whose time has begun, and the calculation settings.
/// Times are calculated on the device, so the screen works fully offline.
library;

import 'package:adhan_dart/adhan_dart.dart' show Madhab;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../../habits/domain/local_day.dart';
import '../application/prayer_log_providers.dart';
import '../application/prayer_providers.dart';
import '../domain/daily_prayer_times.dart';
import '../domain/prayer_city.dart';
import '../domain/prayer_log_status.dart';
import '../domain/prayer_settings.dart';
import 'prayer_labels.dart';

class PrayerScreen extends ConsumerWidget {
  const PrayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(prayerSettingsProvider);
    final day = ref.watch(todayPrayerProvider).value;
    final marks = day == null
        ? const <String, PrayerLogStatus>{}
        : ref
                .watch(prayerMarksProvider(_localDay(day).toUtcMidnight()))
                .value ??
            const <String, PrayerLogStatus>{};

    return Scaffold(
      appBar: AppBar(title: Text(l10n.modulePrayer)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => EmptyState(message: l10n.errorGeneric),
        data: (settings) {
          final city = settings.city;
          return ListView(
            padding: const EdgeInsets.all(KunimSpacing.lg),
            children: [
              if (day == null)
                _SetupCard(onChooseCity: () => _pickCity(context, ref))
              else ...[
                _NextPrayerCard(day: day),
                const SizedBox(height: KunimSpacing.xl),
                _SectionTitle(l10n.prayerToday),
                const SizedBox(height: KunimSpacing.xs),
                Text(
                  l10n.prayerMarkHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: KunimSpacing.sm),
                _TimesCard(
                  day: day,
                  marks: marks,
                  onMark: (slot, current) =>
                      _mark(context, ref, day, slot, current),
                ),
              ],
              const SizedBox(height: KunimSpacing.xl),
              _SectionTitle(l10n.prayerSettingsSection),
              const SizedBox(height: KunimSpacing.sm),
              _SettingRow(
                icon: Icons.location_on_outlined,
                title: l10n.prayerCity,
                value: city == null
                    ? l10n.prayerChooseCity
                    : PrayerLabels.city(l10n, city),
                onTap: () => _pickCity(context, ref),
              ),
              _SettingRow(
                icon: Icons.calculate_outlined,
                title: l10n.onbPrayerMethodLabel,
                value: PrayerLabels.method(l10n, settings.method),
                onTap: () => _pickMethod(context, ref),
              ),
              _SettingRow(
                icon: Icons.wb_sunny_outlined,
                title: l10n.prayerAsrMadhab,
                value: PrayerLabels.madhab(l10n, settings.madhab),
                onTap: () => _pickMadhab(context, ref),
              ),
              const SizedBox(height: KunimSpacing.sm),
              Text(
                l10n.prayerAccuracyNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The city's calendar day the times belong to.
  static LocalDay _localDay(PrayerDay day) =>
      LocalDay(day.now.year, day.now.month, day.now.day);

  PrayerSettings _current(WidgetRef ref) =>
      ref.read(prayerSettingsProvider).value ?? PrayerSettings.defaults;

  Future<void> _mark(
    BuildContext context,
    WidgetRef ref,
    PrayerDay day,
    PrayerSlot slot,
    PrayerLogStatus? current,
  ) async {
    final key = prayerLogKey(slot.kind);
    if (key == null) return;
    final l10n = AppLocalizations.of(context);
    final picked = await showKunimChoiceSheet<_Mark>(
      context: context,
      title: PrayerLabels.prayer(l10n, slot.kind),
      selected: current == null ? null : _Mark.of(current),
      options: [
        (_Mark.jamaah, l10n.prayerStatusJamaah),
        (_Mark.alone, l10n.prayerStatusAlone),
        (_Mark.qaza, l10n.prayerStatusQaza),
        if (current != null) (_Mark.clear, l10n.prayerStatusClear),
      ],
    );
    if (picked == null) return;

    final repository = ref.read(prayerLogRepositoryProvider);
    final status = picked.status;
    if (status == null) {
      await repository.clear(_localDay(day), key);
    } else {
      await repository.mark(_localDay(day), key, status);
    }
  }

  Future<void> _pickCity(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final cities = [...PrayerCity.values]..sort(
        (a, b) => PrayerLabels.city(l10n, a).compareTo(
          PrayerLabels.city(l10n, b),
        ),
      );
    final picked = await showKunimChoiceSheet<PrayerCity>(
      context: context,
      title: l10n.prayerChooseCity,
      selected: _current(ref).city,
      options: [
        for (final city in cities) (city, PrayerLabels.city(l10n, city)),
      ],
    );
    if (picked != null) {
      await ref
          .read(prayerSettingsProvider.notifier)
          .edit((settings) => settings.copyWith(city: picked));
    }
  }

  Future<void> _pickMethod(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showKunimChoiceSheet<PrayerMethod>(
      context: context,
      title: l10n.onbPrayerMethodLabel,
      selected: _current(ref).method,
      options: [
        for (final method in PrayerMethod.values)
          (method, PrayerLabels.method(l10n, method)),
      ],
    );
    if (picked != null) {
      await ref
          .read(prayerSettingsProvider.notifier)
          .edit((settings) => settings.copyWith(method: picked));
    }
  }

  Future<void> _pickMadhab(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showKunimChoiceSheet<Madhab>(
      context: context,
      title: l10n.prayerAsrMadhab,
      selected: _current(ref).madhab,
      options: [
        for (final madhab in Madhab.values)
          (madhab, PrayerLabels.madhab(l10n, madhab)),
      ],
    );
    if (picked != null) {
      await ref
          .read(prayerSettingsProvider.notifier)
          .edit((settings) => settings.copyWith(madhab: picked));
    }
  }
}

/// A choice in the mark sheet; [clear] takes a mark back.
enum _Mark {
  jamaah(PrayerLogStatus.jamaah),
  alone(PrayerLogStatus.alone),
  qaza(PrayerLogStatus.qaza),
  clear(null);

  const _Mark(this.status);

  final PrayerLogStatus? status;

  static _Mark? of(PrayerLogStatus status) {
    return switch (status) {
      PrayerLogStatus.jamaah => _Mark.jamaah,
      PrayerLogStatus.alone => _Mark.alone,
      PrayerLogStatus.qaza => _Mark.qaza,
      PrayerLogStatus.none => null,
    };
  }
}

/// A mark's label, or `null` for no mark.
String? _statusLabel(AppLocalizations l10n, PrayerLogStatus? status) {
  return switch (status) {
    PrayerLogStatus.jamaah => l10n.prayerStatusJamaah,
    PrayerLogStatus.alone => l10n.prayerStatusAlone,
    PrayerLogStatus.qaza => l10n.prayerStatusQaza,
    PrayerLogStatus.none || null => null,
  };
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.onChooseCity});

  final VoidCallback onChooseCity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return HeritageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.mosque_outlined,
            size: 32,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: KunimSpacing.md),
          Text(l10n.prayerSetupTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: KunimSpacing.xs),
          Text(
            l10n.prayerSetupBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: KunimSpacing.lg),
          FilledButton.icon(
            onPressed: onChooseCity,
            icon: const Icon(Icons.location_on_outlined),
            label: Text(l10n.prayerChooseCity),
          ),
        ],
      ),
    );
  }
}

class _NextPrayerCard extends StatelessWidget {
  const _NextPrayerCard({required this.day});

  final PrayerDay day;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final onPrimary = theme.colorScheme.onPrimary;
    final next = day.next;

    return Container(
      padding: const EdgeInsets.all(KunimSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(KunimRadii.extraLarge),
      ),
      child: Row(
        children: [
          Icon(PrayerLabels.icon(next.kind), color: onPrimary, size: 36),
          const SizedBox(width: KunimSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.prayerNext,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: onPrimary.withValues(alpha: .8),
                  ),
                ),
                const SizedBox(height: KunimSpacing.xs),
                Wrap(
                  spacing: KunimSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      PrayerLabels.prayer(l10n, next.kind),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: onPrimary,
                      ),
                    ),
                    Text(
                      PrayerLabels.time(context, next.time),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (day.nextIndex == null)
                      Text(
                        l10n.prayerTomorrow,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: onPrimary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: KunimSpacing.xs),
                Text(
                  PrayerLabels.countdown(l10n, day.untilNext),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimesCard extends StatelessWidget {
  const _TimesCard({
    required this.day,
    required this.marks,
    required this.onMark,
  });

  final PrayerDay day;

  /// Today's marks, keyed by prayer key.
  final Map<String, PrayerLogStatus> marks;
  final void Function(PrayerSlot slot, PrayerLogStatus? current) onMark;

  @override
  Widget build(BuildContext context) {
    return HeritageCard(
      padding: const EdgeInsets.all(KunimSpacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < day.slots.length; i++)
            _row(day.slots[i], isNext: day.nextIndex == i),
        ],
      ),
    );
  }

  Widget _row(PrayerSlot slot, {required bool isNext}) {
    final key = prayerLogKey(slot.kind);
    // A prayer can be marked once its time has begun; sunrise never.
    final markable = key != null && !slot.time.isAfter(day.now);
    final status = key == null ? null : marks[key];
    return _TimeRow(
      slot: slot,
      isNext: isNext,
      markable: markable,
      status: status,
      onTap: markable ? () => onMark(slot, status) : null,
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.slot,
    required this.isNext,
    required this.markable,
    required this.status,
    required this.onTap,
  });

  final PrayerSlot slot;
  final bool isNext;
  final bool markable;
  final PrayerLogStatus? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = isNext ? scheme.onPrimaryContainer : scheme.onSurface;
    final statusLabel = _statusLabel(l10n, status);
    final marked = statusLabel != null;

    return Material(
      color: isNext ? scheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(KunimRadii.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KunimRadii.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KunimSpacing.md,
            vertical: KunimSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                PrayerLabels.icon(slot.kind),
                color: isNext ? scheme.onPrimaryContainer : scheme.secondary,
              ),
              const SizedBox(width: KunimSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      PrayerLabels.prayer(l10n, slot.kind),
                      style: theme.textTheme.titleSmall?.copyWith(color: color),
                    ),
                    if (marked)
                      Text(
                        statusLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isNext
                              ? scheme.onPrimaryContainer
                              : scheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: KunimSpacing.sm),
              Text(
                PrayerLabels.time(context, slot.time),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: isNext ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (markable) ...[
                const SizedBox(width: KunimSpacing.sm),
                Icon(
                  marked
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: scheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: KunimSpacing.sm),
      child: HeritageCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: KunimSpacing.lg,
          vertical: KunimSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: KunimSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  Text(
                    value,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: KunimSpacing.sm),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
