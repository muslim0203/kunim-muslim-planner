// Widget reminders: what the scheduler hands the notification system for the
// widgets the user set a time on.
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/notifications/local_notifier.dart';
import 'package:kunim/core/settings/app_settings.dart';
import 'package:kunim/features/habits/data/habit_log_repository.dart';
import 'package:kunim/features/habits/data/habit_repository.dart';
import 'package:kunim/features/habits/domain/habit_reminder_plan.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/notifications/application/habit_reminder_scheduler.dart';

/// 28 September 2026, 06:00 on the device's own clock.
final _morning = DateTime(2026, 9, 28, 6);

void main() {
  // The scheduler listens for app resume through the widgets binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late HabitRepository habits;
  late FakeNotifier notifier;
  late ProviderContainer container;

  /// The app root watches the scheduler for the whole session; the habits
  /// stream it listens to only stays alive while something holds it, so the
  /// test holds it the same way.
  late ProviderSubscription<HabitReminderScheduler> scheduler;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    habits = HabitRepository(db, onLocalWrite: () {});
    notifier = FakeNotifier();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        localNotifierProvider.overrideWithValue(notifier),
        habitReminderClockProvider.overrideWithValue(() => _morning),
      ],
    );
    scheduler = container.listen(habitReminderSchedulerProvider, (_, __) {});
  });

  tearDown(() async {
    scheduler.close();
    container.dispose();
    await db.close();
  });

  /// Lets the widgets stream deliver the write that just happened: in the
  /// app the stream is what triggers a reschedule, so a plan built before it
  /// arrives would be built from stale rows.
  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> reschedule() async {
    await settle();
    await scheduler.read().reschedule();
  }

  test('a widget with a time is reminded in the app language', () async {
    await habits.createHabit(title: 'Kitob o‘qish', reminderMinutes: 450);

    await reschedule();

    final l10n = lookupAppLocalizations(const Locale('uz'));
    expect(notifier.replacedRange, (
      HabitReminderPlan.firstId,
      HabitReminderPlan.idCount,
    ));
    expect(notifier.channel?.id, HabitReminderScheduler.channelId);
    expect(notifier.channel?.name, l10n.reminderChannelHabit);
    expect(notifier.scheduled, hasLength(HabitReminderPlan.days));
    final first = notifier.scheduled.first;
    expect(first.title, 'Kitob o‘qish');
    expect(first.body, l10n.reminderHabitBody('7:30'));
    expect(first.at.toLocal(), DateTime(2026, 9, 28, 7, 30));
  });

  test('a widget without a time is left alone', () async {
    await habits.createHabit(title: 'Zikr');

    await reschedule();

    // The range is still cleared, so a time that was removed stops firing.
    expect(notifier.replacedRange, isNotNull);
    expect(notifier.scheduled, isEmpty);
  });

  test("today's reminder goes once today's work is logged", () async {
    final id = await habits.createHabit(
      title: 'Kitob o‘qish',
      reminderMinutes: 450,
    );
    await HabitLogRepository(db, onLocalWrite: () {}).logCompletion(
      habitId: id,
      day: LocalDay.fromLocalDateTime(_morning),
    );

    await reschedule();

    expect(notifier.scheduled, hasLength(HabitReminderPlan.days - 1));
    expect(
      notifier.scheduled.first.at.toLocal(),
      DateTime(2026, 9, 29, 7, 30),
    );
  });

  test('an archived widget stops reminding', () async {
    final id = await habits.createHabit(
      title: 'Kitob o‘qish',
      reminderMinutes: 450,
    );
    await reschedule();
    expect(notifier.scheduled, isNotEmpty);

    await habits.archiveHabit(id);
    await reschedule();

    expect(notifier.scheduled, isEmpty);
  });

  test('the language the user reads is the language of the reminder', () async {
    await habits.createHabit(title: 'Kitob o‘qish', reminderMinutes: 450);
    await container
        .read(appSettingsProvider.notifier)
        .setLanguage(AppLanguage.ru);

    await reschedule();

    final ru = lookupAppLocalizations(const Locale('ru'));
    expect(notifier.channel?.name, ru.reminderChannelHabit);
    expect(notifier.scheduled.first.body, ru.reminderHabitBody('7:30'));
  });
}

/// Records what the scheduler asks of the notification system.
class FakeNotifier implements LocalNotifier {
  (int, int)? replacedRange;
  NotificationChannelInfo? channel;
  List<ScheduledNotification> scheduled = const [];

  @override
  Future<bool> areEnabled() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  bool get managesExactAlarms => false;

  @override
  Future<bool> exactAlarmsAllowed() async => true;

  @override
  Future<void> openExactAlarmSettings() async {}

  @override
  Future<void> replaceRange({
    required int firstId,
    required int count,
    required NotificationChannelInfo channel,
    required List<ScheduledNotification> notifications,
  }) async {
    replacedRange = (firstId, count);
    this.channel = channel;
    scheduled = List.of(notifications);
  }
}
