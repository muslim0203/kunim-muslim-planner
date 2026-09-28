/// Which widget reminders to schedule, computed purely from the widgets and
/// the current instant.
///
/// A widget's time is minutes from LOCAL midnight (`Habits.reminderMinutes`),
/// so the reminder is built from the device's own wall clock: the same widget
/// fires at 07:30 wherever its owner wakes up, which is what a daily task
/// means. That is also why the window is short — [days] days, refreshed
/// whenever the app starts, resumes or a widget changes, the same way prayer
/// reminders work while nothing runs in the background yet.
library;

import 'habit_schedule.dart';
import 'local_day.dart';

/// One widget, reduced to what the plan needs. Keeps this file free of the
/// Drift row and of the application layer's read model.
class HabitReminderInput {
  const HabitReminderInput({
    required this.habitId,
    required this.title,
    required this.schedule,
    required this.minutes,
    required this.doneToday,
  });

  final String habitId;
  final String title;
  final HabitSchedule schedule;

  /// Minutes from local midnight, or null for a widget with no fixed time —
  /// those get no reminder.
  final int? minutes;

  /// Whether today's work is already finished, in which case today's
  /// reminder is dropped (tomorrow's still stands).
  final bool doneToday;
}

class HabitReminder {
  const HabitReminder({
    required this.id,
    required this.habitId,
    required this.title,
    required this.at,
    required this.minutes,
  });

  /// Stable per widget and day, so a reschedule replaces rather than
  /// duplicates.
  final int id;
  final String habitId;
  final String title;

  /// When it fires, as a UTC instant.
  final DateTime at;

  /// The widget's own time, for the "07:30" in the message.
  final int minutes;
}

abstract final class HabitReminderPlan {
  /// Prayer reminders own 1000..1069 (`PrayerReminderPlan`); this range
  /// starts past them and must not overlap.
  static const int firstId = 2000;
  static const int days = 3;

  /// How many widgets get reminders at once. iOS allows 64 pending
  /// notifications in total and prayers already hold 70 ids worth of
  /// schedule, so this stays small on purpose; widgets beyond it (ordered
  /// by time of day) simply have no reminder.
  static const int widgets = 10;

  /// Size of the id range owned by widget reminders.
  static int get idCount => days * widgets;

  static List<HabitReminder> build({
    required List<HabitReminderInput> inputs,
    required DateTime now,
  }) {
    final timed = inputs.where((input) => input.minutes != null).toList()
      ..sort((a, b) => a.minutes!.compareTo(b.minutes!));
    final today = LocalDay.fromLocalDateTime(now);
    final nowUtc = now.toUtc();
    final result = <HabitReminder>[];

    for (var slot = 0; slot < timed.length && slot < widgets; slot++) {
      final input = timed[slot];
      final minutes = input.minutes!;
      for (var day = 0; day < days; day++) {
        // Today's reminder is pointless once the work is done; a later day
        // is not yet decided, so it is always scheduled.
        if (day == 0 && input.doneToday) continue;
        final date = today.addDays(day);
        if (!input.schedule.isScheduledOn(date)) continue;
        final at = DateTime(
          date.year,
          date.month,
          date.day,
          minutes ~/ 60,
          minutes % 60,
        ).toUtc();
        if (!at.isAfter(nowUtc)) continue;
        result.add(
          HabitReminder(
            id: firstId + day * widgets + slot,
            habitId: input.habitId,
            title: input.title,
            at: at,
            minutes: minutes,
          ),
        );
      }
    }
    return result;
  }
}
