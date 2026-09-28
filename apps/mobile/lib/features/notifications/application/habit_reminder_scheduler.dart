/// Keeps the scheduled widget reminders in step with the widgets themselves.
///
/// A widget with a time of day (`Habits.reminderMinutes`) reminds its owner
/// at that time; one without stays silent. Every run replaces the whole
/// reminder id range, so it is safe to run as often as needed, and runs are
/// queued so two never interleave — the same shape as
/// `PrayerReminderScheduler`, whose id range this one deliberately sits past.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../core/notifications/local_notifier.dart';
import '../../../core/settings/app_settings.dart';
import '../../habits/application/habits_today_provider.dart';
import '../../habits/domain/habit_reminder_plan.dart';

/// The clock the plan is built from. Overridden in tests.
final habitReminderClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class HabitReminderScheduler {
  HabitReminderScheduler(this._ref);

  final Ref _ref;
  Future<void> _last = Future.value();

  static const String channelId = 'habit_reminders';

  /// Queues a run and completes when it (and every earlier one) is done.
  Future<void> reschedule() {
    final run = _last.then((_) => _run()).catchError((Object error) {
      // Reminders are best-effort; a failure must never break the app. The
      // next start, resume or widget edit tries again.
      debugPrint('Widget reminders not rescheduled: ${error.runtimeType}');
    });
    return _last = run;
  }

  Future<void> _run() async {
    final notifier = _ref.read(localNotifierProvider);
    final habits = await _ref.read(allHabitsWithTodayProvider.future);
    final l10n = lookupAppLocalizations(
      _ref.read(appSettingsProvider).language.locale,
    );
    final plan = HabitReminderPlan.build(
      inputs: [
        for (final habit in habits)
          HabitReminderInput(
            habitId: habit.habit.id,
            title: habit.habit.title,
            schedule: habit.schedule,
            minutes: habit.habit.reminderMinutes,
            doneToday: habit.isDone,
          ),
      ],
      now: _ref.read(habitReminderClockProvider)(),
    );

    await notifier.replaceRange(
      firstId: HabitReminderPlan.firstId,
      count: HabitReminderPlan.idCount,
      channel: NotificationChannelInfo(
        id: channelId,
        name: l10n.reminderChannelHabit,
        description: l10n.reminderChannelHabitDescription,
      ),
      notifications: [
        for (final reminder in plan)
          ScheduledNotification(
            id: reminder.id,
            at: reminder.at,
            title: reminder.title,
            body: l10n.reminderHabitBody(clockLabel(reminder.minutes)),
          ),
      ],
    );
  }

  /// "7:30" from minutes past midnight, without needing a BuildContext —
  /// the same shape the in-app timetable and the prayer reminders use.
  static String clockLabel(int minutes) =>
      '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
}

/// Reading this once (the app root does) keeps widget reminders scheduled:
/// now, whenever a widget or today's progress changes, on a language change
/// and each time the app comes back to the foreground, which also slides the
/// reminder window forward.
final habitReminderSchedulerProvider = Provider<HabitReminderScheduler>((ref) {
  final scheduler = HabitReminderScheduler(ref);
  ref.listen(allHabitsWithTodayProvider, (_, __) => scheduler.reschedule());
  ref.listen(
    appSettingsProvider.select((settings) => settings.language),
    (_, __) => scheduler.reschedule(),
  );
  final lifecycle = AppLifecycleListener(onResume: scheduler.reschedule);
  ref.onDispose(lifecycle.dispose);
  unawaited(scheduler.reschedule());
  return scheduler;
});
