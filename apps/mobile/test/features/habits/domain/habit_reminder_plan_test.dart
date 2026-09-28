// Which widget reminders get scheduled: only widgets with a time, only days
// the widget is due, never in the past, and never for work already done.
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/habits/domain/habit_reminder_plan.dart';
import 'package:kunim/features/habits/domain/habit_schedule.dart';

HabitReminderInput input({
  String habitId = 'h1',
  String title = 'Kitob o‘qish',
  int? minutes = 450, // 07:30
  HabitSchedule schedule = const HabitSchedule.everyDay(),
  bool doneToday = false,
}) {
  return HabitReminderInput(
    habitId: habitId,
    title: title,
    schedule: schedule,
    minutes: minutes,
    doneToday: doneToday,
  );
}

/// A local wall-clock instant, the way the device's own clock reads.
DateTime local(int year, int month, int day, [int hour = 6, int minute = 0]) =>
    DateTime(year, month, day, hour, minute);

void main() {
  test('a widget with no time is never a reminder', () {
    final plan = HabitReminderPlan.build(
      inputs: [input(minutes: null)],
      now: local(2026, 9, 28),
    );

    expect(plan, isEmpty);
  });

  test('an every-day widget is scheduled for the whole window', () {
    final plan = HabitReminderPlan.build(
      inputs: [input()],
      now: local(2026, 9, 28),
    );

    expect(plan, hasLength(HabitReminderPlan.days));
    expect(
      plan.map((reminder) => reminder.at.toLocal()),
      [
        local(2026, 9, 28, 7, 30),
        local(2026, 9, 29, 7, 30),
        local(2026, 9, 30, 7, 30),
      ],
    );
    expect(plan.every((reminder) => reminder.title == 'Kitob o‘qish'), isTrue);
  });

  test('a time already past today is skipped, tomorrow is not', () {
    final plan = HabitReminderPlan.build(
      inputs: [input()],
      now: local(2026, 9, 28, 9, 0),
    );

    expect(plan, hasLength(HabitReminderPlan.days - 1));
    expect(plan.first.at.toLocal(), local(2026, 9, 29, 7, 30));
  });

  test("today's reminder is dropped once today's work is done", () {
    final plan = HabitReminderPlan.build(
      inputs: [input(doneToday: true)],
      now: local(2026, 9, 28),
    );

    expect(
      plan.map((reminder) => reminder.at.toLocal()),
      [local(2026, 9, 29, 7, 30), local(2026, 9, 30, 7, 30)],
    );
  });

  test('a weekday schedule only reminds on its own days', () {
    // 2026-09-28 is a Monday, so Monday and Wednesday are in the window and
    // Tuesday is not.
    final plan = HabitReminderPlan.build(
      inputs: [
        input(
          schedule: const HabitSchedule.specificWeekdays({
            DateTime.monday,
            DateTime.wednesday,
          }),
        ),
      ],
      now: local(2026, 9, 28),
    );

    expect(
      plan.map((reminder) => reminder.at.toLocal()),
      [local(2026, 9, 28, 7, 30), local(2026, 9, 30, 7, 30)],
    );
  });

  test('ids are unique, stable per day and inside the range', () {
    final plan = HabitReminderPlan.build(
      inputs: [
        input(habitId: 'h1', minutes: 450),
        input(habitId: 'h2', minutes: 1200),
      ],
      now: local(2026, 9, 28),
    );
    final ids = plan.map((reminder) => reminder.id).toList();

    expect(ids.toSet(), hasLength(ids.length));
    expect(
      ids.every(
        (id) =>
            id >= HabitReminderPlan.firstId &&
            id < HabitReminderPlan.firstId + HabitReminderPlan.idCount,
      ),
      isTrue,
    );
    // Same widget, same slot on every day of the window.
    final first = plan.where((reminder) => reminder.habitId == 'h1').toList();
    expect(
      first.map((reminder) => reminder.id),
      [
        HabitReminderPlan.firstId,
        HabitReminderPlan.firstId + HabitReminderPlan.widgets,
        HabitReminderPlan.firstId + 2 * HabitReminderPlan.widgets,
      ],
    );
  });

  test('the earliest widgets win when there are more than the range holds', () {
    final plan = HabitReminderPlan.build(
      inputs: [
        for (var i = 0; i < HabitReminderPlan.widgets + 3; i++)
          input(habitId: 'h$i', minutes: 1439 - i),
      ],
      now: local(2026, 9, 28),
    );
    final scheduled = plan.map((reminder) => reminder.habitId).toSet();

    expect(scheduled, hasLength(HabitReminderPlan.widgets));
    // Sorted by time of day, so the LAST built (smallest minutes) are in.
    expect(scheduled, contains('h${HabitReminderPlan.widgets + 2}'));
    expect(scheduled, isNot(contains('h0')));
  });
}
