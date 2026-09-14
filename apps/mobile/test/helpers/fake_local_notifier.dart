import 'package:kunim/core/notifications/local_notifier.dart';

/// Records what the app asks of the notification system, with configurable
/// permission answers.
class FakeLocalNotifier implements LocalNotifier {
  FakeLocalNotifier({
    this.enabled = false,
    this.grants = true,
    this.managesExactAlarms = false,
    this.exactAllowed = true,
  });

  bool enabled;
  final bool grants;
  bool exactAllowed;

  @override
  final bool managesExactAlarms;

  int permissionRequests = 0;
  int exactSettingsOpened = 0;
  (int, int)? replacedRange;
  NotificationChannelInfo? channel;
  List<ScheduledNotification> scheduled = const [];

  @override
  Future<bool> areEnabled() async => enabled;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    enabled = grants;
    return grants;
  }

  @override
  Future<bool> exactAlarmsAllowed() async => exactAllowed;

  @override
  Future<void> openExactAlarmSettings() async {
    exactSettingsOpened++;
  }

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
