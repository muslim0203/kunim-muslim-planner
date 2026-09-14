import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../core/db/app_database.dart';
import '../../../core/notifications/local_notifier.dart';
import '../../../core/settings/app_settings.dart';
import '../../prayer/application/prayer_providers.dart';
import '../../prayer/presentation/prayer_labels.dart';
import '../data/prayer_reminder_store.dart';
import '../domain/prayer_reminder_plan.dart';
import '../domain/prayer_reminder_settings.dart';

final prayerReminderStoreProvider = Provider<PrayerReminderStore>((ref) {
  return PrayerReminderStore(ref.watch(appDatabaseProvider));
});

class PrayerReminderSettingsController
    extends AsyncNotifier<PrayerReminderSettings> {
  @override
  Future<PrayerReminderSettings> build() =>
      ref.watch(prayerReminderStoreProvider).load();

  /// Applies [change] to the current settings, shows the result at once and
  /// saves it.
  Future<void> edit(
    PrayerReminderSettings Function(PrayerReminderSettings) change,
  ) async {
    final current = state.value ?? await future;
    final next = change(current);
    if (next == current) return;
    state = AsyncData(next);
    await ref.read(prayerReminderStoreProvider).save(next);
  }
}

final prayerReminderSettingsProvider = AsyncNotifierProvider<
    PrayerReminderSettingsController, PrayerReminderSettings>(
  PrayerReminderSettingsController.new,
);

/// Whether reminders can fire at the exact minute. Invalidate it when the
/// user comes back from the system setting.
final exactAlarmsAllowedProvider = FutureProvider<bool>((ref) {
  return ref.watch(localNotifierProvider).exactAlarmsAllowed();
});

/// Keeps the scheduled prayer reminders in step with the settings.
///
/// Every run replaces the whole reminder id range, so it is safe to run as
/// often as needed; runs are queued so two never interleave.
class PrayerReminderScheduler {
  PrayerReminderScheduler(this._ref);

  final Ref _ref;
  Future<void> _last = Future.value();

  static const String channelId = 'prayer_times';

  /// Queues a run and completes when it (and every earlier one) is done.
  Future<void> reschedule() {
    final run = _last.then((_) => _run()).catchError((Object error) {
      // Reminders are best-effort; a failure must never break the app. The
      // next start, resume or settings change tries again.
      debugPrint('Prayer reminders not rescheduled: ${error.runtimeType}');
    });
    return _last = run;
  }

  Future<void> _run() async {
    final notifier = _ref.read(localNotifierProvider);
    final prayer = await _ref.read(prayerSettingsProvider.future);
    final reminders = await _ref.read(prayerReminderSettingsProvider.future);
    final l10n = lookupAppLocalizations(
      _ref.read(appSettingsProvider).language.locale,
    );
    final now = _ref.read(prayerClockProvider)();
    final city = prayer.city;

    final plan = PrayerReminderPlan.build(
      prayer: prayer,
      reminders: reminders,
      now: now,
    );
    await notifier.replaceRange(
      firstId: PrayerReminderPlan.firstId,
      count: PrayerReminderPlan.idCount,
      channel: NotificationChannelInfo(
        id: channelId,
        name: l10n.reminderChannelPrayer,
        description: l10n.reminderChannelPrayerDescription,
      ),
      notifications: [
        if (city != null)
          for (final reminder in plan)
            _notificationFor(reminder, l10n, PrayerLabels.city(l10n, city)),
      ],
    );
  }

  static ScheduledNotification _notificationFor(
    PrayerReminder reminder,
    AppLocalizations l10n,
    String cityName,
  ) {
    final name = PrayerLabels.prayer(l10n, reminder.kind);
    final time = _clock(reminder.prayerTime);
    final atTime = reminder.leadMinutes == 0;
    return ScheduledNotification(
      id: reminder.id,
      at: reminder.at,
      title: atTime
          ? l10n.reminderPrayerNowTitle(name)
          : l10n.reminderPrayerSoonTitle(name, reminder.leadMinutes),
      body: atTime
          ? l10n.reminderPrayerNowBody(cityName, time)
          : l10n.reminderPrayerSoonBody(name, time),
    );
  }

  /// Same "4:28" / "12:20" style as the in-app timetable, without needing a
  /// BuildContext.
  static String _clock(DateTime time) =>
      '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
}

/// Reading this once (the app root does) keeps reminders scheduled: now, on
/// every relevant settings change, and each time the app comes back to the
/// foreground, which also slides the reminder window forward.
final prayerReminderSchedulerProvider =
    Provider<PrayerReminderScheduler>((ref) {
  final scheduler = PrayerReminderScheduler(ref);
  ref.listen(prayerSettingsProvider, (_, __) => scheduler.reschedule());
  ref.listen(prayerReminderSettingsProvider, (_, __) => scheduler.reschedule());
  ref.listen(
    appSettingsProvider.select((settings) => settings.language),
    (_, __) => scheduler.reschedule(),
  );
  final lifecycle = AppLifecycleListener(onResume: scheduler.reschedule);
  ref.onDispose(lifecycle.dispose);
  unawaited(scheduler.reschedule());
  return scheduler;
});
