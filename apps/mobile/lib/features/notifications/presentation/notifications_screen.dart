/// Notification settings. Today that is prayer reminders: on or off, which
/// prayers and how early. `PrayerReminderScheduler` does the scheduling;
/// this screen edits the settings and asks for the permissions they need.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/notifications/local_notifier.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../../../core/db/app_database.dart';
import '../../habits/application/habits_today_provider.dart';
import '../../habits/domain/habit_kind.dart';
import '../../habits/presentation/habit_editor.dart';
import '../../habits/presentation/habit_kind_labels.dart';
import '../../prayer/application/prayer_providers.dart';
import '../../prayer/domain/daily_prayer_times.dart';
import '../../prayer/presentation/prayer_labels.dart';
import '../application/notification_providers.dart';
import '../domain/prayer_reminder_settings.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Exact alarms are granted in system settings; re-check on return.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(exactAlarmsAllowedProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prayerAsync = ref.watch(prayerSettingsProvider);
    final remindersAsync = ref.watch(prayerReminderSettingsProvider);
    final notifier = ref.watch(localNotifierProvider);
    final exactAllowed = ref.watch(exactAlarmsAllowedProvider).value ?? true;
    final prayer = prayerAsync.value;
    final reminders = remindersAsync.value;
    final muted = theme.colorScheme.onSurfaceVariant;

    final Widget body;
    if (prayer != null && reminders != null) {
      body = ListView(
        padding: const EdgeInsets.all(KunimSpacing.lg),
        children: [
          Text(
            l10n.notifScreenIntro,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: KunimSpacing.lg),
          if (prayer.city == null)
            _NeedCityCard(
              onChooseCity: () => context.go(KunimRoutes.settingsPrayer),
            )
          else ...[
            HeritageCard(
              padding: const EdgeInsets.symmetric(vertical: KunimSpacing.xs),
              child: SwitchListTile(
                secondary: Icon(
                  Icons.notifications_active_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(l10n.notifPrayerTitle),
                subtitle: Text(l10n.notifPrayerSubtitle),
                value: reminders.enabled,
                onChanged: _setEnabled,
              ),
            ),
            if (reminders.enabled) ...[
              if (notifier.managesExactAlarms && !exactAllowed) ...[
                const SizedBox(height: KunimSpacing.md),
                _ExactAlarmCard(onAllow: _allowExactAlarms),
              ],
              const SizedBox(height: KunimSpacing.xl),
              Text(l10n.notifWhichPrayers, style: theme.textTheme.titleMedium),
              const SizedBox(height: KunimSpacing.sm),
              HeritageCard(
                padding: const EdgeInsets.symmetric(vertical: KunimSpacing.xs),
                child: Column(
                  children: [
                    for (final kind in PrayerReminderSettings.selectable)
                      SwitchListTile(
                        secondary: Icon(
                          PrayerLabels.icon(kind),
                          color: theme.colorScheme.secondary,
                        ),
                        title: Text(PrayerLabels.prayer(l10n, kind)),
                        value: reminders.prayers.contains(kind),
                        onChanged: (on) => _togglePrayer(kind, on),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: KunimSpacing.lg),
              _ChoiceRow(
                icon: Icons.schedule_rounded,
                title: l10n.notifLeadTime,
                value: _leadLabel(l10n, reminders.leadMinutes),
                onTap: () => _pickLead(reminders.leadMinutes),
              ),
              const SizedBox(height: KunimSpacing.sm),
              Text(
                l10n.notifWindowNote,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ],
          // Widget reminders are scheduled from each widget's own hour, with
          // no switch anywhere — so this screen used to say "reminders are
          // off" while a dozen of them were armed. They are listed here, with
          // the hour they fire at, and open the widget that owns them.
          const SizedBox(height: KunimSpacing.xl),
          _WidgetReminders(
            onEdit: (habit) => showHabitEditor(context, habit: habit),
          ),
        ],
      );
    } else if (prayerAsync.hasError || remindersAsync.hasError) {
      body = EmptyState(message: l10n.errorGeneric);
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsNotifications)),
      body: body,
    );
  }

  Future<void> _setEnabled(bool on) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (on) {
      final notifier = ref.read(localNotifierProvider);
      final allowed =
          await notifier.areEnabled() || await notifier.requestPermission();
      if (!allowed) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.notifPermissionDenied)));
        return;
      }
    }
    await _edit((settings) => settings.copyWith(enabled: on));
  }

  Future<void> _togglePrayer(PrayerKind kind, bool on) {
    return _edit(
      (settings) => settings.copyWith(
        prayers: on
            ? {...settings.prayers, kind}
            : ({...settings.prayers}..remove(kind)),
      ),
    );
  }

  Future<void> _allowExactAlarms() async {
    await ref.read(localNotifierProvider).openExactAlarmSettings();
    if (mounted) ref.invalidate(exactAlarmsAllowedProvider);
  }

  Future<void> _pickLead(int current) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showKunimChoiceSheet<int>(
      context: context,
      title: l10n.notifLeadTime,
      selected: current,
      options: [
        for (final minutes in PrayerReminderSettings.leadChoices)
          (minutes, _leadLabel(l10n, minutes)),
      ],
    );
    if (picked != null) {
      await _edit((settings) => settings.copyWith(leadMinutes: picked));
    }
  }

  Future<void> _edit(
    PrayerReminderSettings Function(PrayerReminderSettings) change,
  ) {
    return ref.read(prayerReminderSettingsProvider.notifier).edit(change);
  }

  static String _leadLabel(AppLocalizations l10n, int minutes) =>
      minutes == 0 ? l10n.notifLeadAtTime : l10n.notifLeadMinutes(minutes);
}

class _NeedCityCard extends StatelessWidget {
  const _NeedCityCard({required this.onChooseCity});

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
            Icons.location_on_outlined,
            size: 32,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: KunimSpacing.md),
          Text(l10n.notifNeedCityTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: KunimSpacing.xs),
          Text(
            l10n.notifNeedCityBody,
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

class _ExactAlarmCard extends StatelessWidget {
  const _ExactAlarmCard({required this.onAllow});

  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final onContainer = theme.colorScheme.onTertiaryContainer;
    return HeritageCard(
      color: theme.colorScheme.tertiaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, color: onContainer),
              const SizedBox(width: KunimSpacing.sm),
              Expanded(
                child: Text(
                  l10n.notifExactTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: onContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KunimSpacing.xs),
          Text(
            l10n.notifExactBody,
            style: theme.textTheme.bodyMedium?.copyWith(color: onContainer),
          ),
          const SizedBox(height: KunimSpacing.md),
          FilledButton.tonal(
            onPressed: onAllow,
            child: Text(l10n.notifExactAction),
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
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
    return HeritageCard(
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
    );
  }
}

/// The widgets that carry a reminder hour.
///
/// Read-only here on purpose: the hour belongs to the widget, so this lists
/// what is armed and hands editing back to the widget's own editor rather
/// than becoming a second place that sets the same field.
class _WidgetReminders extends ConsumerWidget {
  const _WidgetReminders({required this.onEdit});

  final void Function(Habit habit) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final habits = ref.watch(habitsForTodayProvider).value ?? const [];
    final withTime = [
      for (final habit in habits)
        if (habit.habit.reminderMinutes != null) habit,
    ]..sort(
        (a, b) => a.habit.reminderMinutes!.compareTo(b.habit.reminderMinutes!),
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.notifWidgetsTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: KunimSpacing.xs),
        Text(
          withTime.isEmpty ? l10n.notifWidgetsNone : l10n.notifWidgetsNote,
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        if (withTime.isNotEmpty) ...[
          const SizedBox(height: KunimSpacing.md),
          HeritageCard(
            padding: const EdgeInsets.symmetric(vertical: KunimSpacing.xs),
            child: Column(
              children: [
                for (final habit in withTime)
                  ListTile(
                    leading: Icon(
                      habitKindIcon(HabitKind.fromCode(habit.habit.kind)),
                      color: habitKindColor(
                        HabitKind.fromCode(habit.habit.kind),
                      ),
                    ),
                    title: Text(habit.habit.title),
                    trailing: Text(
                      MaterialLocalizations.of(context).formatTimeOfDay(
                        habitTimeOfDay(habit.habit.reminderMinutes)!,
                        alwaysUse24HourFormat: true,
                      ),
                      style: theme.textTheme.labelLarge,
                    ),
                    onTap: () => onEdit(habit.habit),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
