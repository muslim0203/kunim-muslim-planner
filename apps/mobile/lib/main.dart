import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/db/app_database.dart';
import 'core/notifications/local_notifier.dart';
import 'core/notifications/plugin_local_notifier.dart';
import 'core/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open the database before the first frame so saved settings (language,
  // theme) apply immediately instead of flashing the defaults.
  // Phase 1+ will also add Firebase.initializeApp() and Sentry here
  // (docs/plan.md section 2, main.dart responsibilities).
  final db = AppDatabase();
  var settings = AppSettings.defaults;
  try {
    settings = await AppSettingsStore(db).load();
  } catch (error) {
    // Settings are a convenience; never block app start on them.
    debugPrint('Could not load saved settings: ${error.runtimeType}');
  }

  // Local notifications (prayer reminders). If the plugin cannot start, the
  // app still runs; reminders simply stay off.
  LocalNotifier notifier = const DisabledLocalNotifier();
  try {
    final plugin = PluginLocalNotifier();
    await plugin.initialize();
    notifier = plugin;
  } catch (error) {
    final code = error is PlatformException ? ' (${error.code})' : '';
    debugPrint('Local notifications unavailable: ${error.runtimeType}$code');
  }

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialAppSettingsProvider.overrideWithValue(settings),
        localNotifierProvider.overrideWithValue(notifier),
      ],
      child: const KunimApp(),
    ),
  );
}
