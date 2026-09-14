import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'local_notifier.dart';

/// [LocalNotifier] backed by `flutter_local_notifications`.
///
/// Times are scheduled in [tz.UTC]: callers pass absolute instants, so no
/// time zone database has to be loaded and the device's own zone never
/// shifts a reminder.
class PluginLocalNotifier implements LocalNotifier {
  PluginLocalNotifier({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        // Monochrome status bar icon: res/drawable-*/ic_stat_kunim.png.
        android: AndroidInitializationSettings('ic_stat_kunim'),
        // Permission is asked when the user turns reminders on, not at
        // launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
  }

  @override
  Future<bool> areEnabled() async {
    final android = _android;
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _ios;
    if (ios != null) {
      return (await ios.checkPermissions())?.isAlertEnabled ?? false;
    }
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    final android = _android;
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _ios;
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  @override
  bool get managesExactAlarms => _android != null;

  @override
  Future<bool> exactAlarmsAllowed() async {
    final android = _android;
    if (android == null) return true;
    return await android.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<void> openExactAlarmSettings() async {
    await _android?.requestExactAlarmsPermission();
  }

  @override
  Future<void> replaceRange({
    required int firstId,
    required int count,
    required NotificationChannelInfo channel,
    required List<ScheduledNotification> notifications,
  }) async {
    for (var id = firstId; id < firstId + count; id++) {
      await _plugin.cancel(id: id);
    }
    if (notifications.isEmpty) return;

    // Without the exact-alarm permission an exact schedule throws, so fall
    // back to an inexact one; the settings screen explains the delay.
    final mode = await exactAlarmsAllowed()
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    for (final notification in notifications) {
      await _plugin.zonedSchedule(
        id: notification.id,
        scheduledDate: tz.TZDateTime.from(notification.at, tz.UTC),
        notificationDetails: details,
        androidScheduleMode: mode,
        title: notification.title,
        body: notification.body,
      );
    }
  }
}
