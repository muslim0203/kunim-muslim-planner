import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Phase 0 has no platform channels registered yet. Pigeon-generated
    // bridges (Screen Time / DeviceActivity) are wired here starting
    // Phase 6 -- see docs/plan.md section 2.
    // flutter_local_notifications: lets prayer reminders show while the
    // app is in the foreground.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
