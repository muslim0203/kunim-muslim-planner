/// On-device notifications behind a small interface, so features schedule
/// reminders without touching the plugin and tests can hand in a fake.
///
/// `main.dart` overrides [localNotifierProvider] with the plugin-backed
/// implementation; every other entry point (widget tests, previews) gets
/// [DisabledLocalNotifier], which never touches a platform channel.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationChannelInfo {
  const NotificationChannelInfo({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}

class ScheduledNotification {
  const ScheduledNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  final int id;

  /// When to show it, as a UTC instant.
  final DateTime at;
  final String title;
  final String body;
}

abstract interface class LocalNotifier {
  /// Whether the user currently allows this app's notifications.
  Future<bool> areEnabled();

  /// Shows the system permission prompt where there is one. Returns whether
  /// notifications are allowed afterwards.
  Future<bool> requestPermission();

  /// Android only: exact alarms are a separate, user-granted permission.
  bool get managesExactAlarms;

  /// Whether reminders can fire at the exact minute. Always true where the
  /// platform has no such restriction.
  Future<bool> exactAlarmsAllowed();

  /// Opens the system screen where exact alarms are granted.
  Future<void> openExactAlarmSettings();

  /// Cancels every notification with an id in `[firstId, firstId + count)`
  /// and schedules [notifications] (whose ids must lie in that range).
  Future<void> replaceRange({
    required int firstId,
    required int count,
    required NotificationChannelInfo channel,
    required List<ScheduledNotification> notifications,
  });
}

class DisabledLocalNotifier implements LocalNotifier {
  const DisabledLocalNotifier();

  @override
  Future<bool> areEnabled() async => false;

  @override
  Future<bool> requestPermission() async => false;

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
  }) async {}
}

final localNotifierProvider = Provider<LocalNotifier>(
  (ref) => const DisabledLocalNotifier(),
);
