/// The prayer module: today's times for the chosen city, the next prayer and
/// the calculation settings. Times are calculated on the device, so the
/// screen works fully offline.
library;

import 'package:adhan_dart/adhan_dart.dart' show Madhab;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../application/prayer_providers.dart';
import '../domain/daily_prayer_times.dart';
import '../domain/prayer_city.dart';
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
                const SizedBox(height: KunimSpacing.sm),
                _TimesCard(day: day),
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

  PrayerSettings _current(WidgetRef ref) =>
      ref.read(prayerSettingsProvider).value ?? PrayerSettings.defaults;

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
  const _TimesCard({required this.day});

  final PrayerDay day;

  @override
  Widget build(BuildContext context) {
    return HeritageCard(
      padding: const EdgeInsets.all(KunimSpacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < day.slots.length; i++)
            _TimeRow(slot: day.slots[i], isNext: day.nextIndex == i),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.slot, required this.isNext});

  final PrayerSlot slot;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = isNext ? scheme.onPrimaryContainer : scheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KunimSpacing.md,
        vertical: KunimSpacing.md,
      ),
      decoration: isNext
          ? BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(KunimRadii.medium),
            )
          : null,
      child: Row(
        children: [
          Icon(
            PrayerLabels.icon(slot.kind),
            color: isNext ? scheme.onPrimaryContainer : scheme.secondary,
          ),
          const SizedBox(width: KunimSpacing.md),
          Expanded(
            child: Text(
              PrayerLabels.prayer(l10n, slot.kind),
              style: theme.textTheme.titleSmall?.copyWith(color: color),
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
        ],
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
