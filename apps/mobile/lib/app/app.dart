import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import '../core/settings/app_settings.dart';
import '../core/sync/sync_triggers.dart';
import '../features/notifications/application/notification_providers.dart';
import 'l10n/gen/app_localizations.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Root widget of the KUNIM app.
///
/// The interface language comes from [appSettingsProvider], not from the
/// device locale: Uzbek is the primary language and the default, and the
/// user switches languages in Settings.
class KunimApp extends ConsumerWidget {
  const KunimApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(appSettingsProvider);
    final uzbekCyrillic = settings.language == AppLanguage.uzCyrl;
    // Arms prayer reminder scheduling for the lifetime of the app.
    ref.watch(prayerReminderSchedulerProvider);
    // Restores a saved session (which syncs it) and arms the automatic
    // sync triggers; a cycle only runs while an account is signed in.
    ref.listen(authControllerProvider, (previous, next) {});
    ref.watch(syncTriggerSchedulerProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      routerConfig: router,
      theme: uzbekCyrillic ? KunimTheme.lightSystemFont : KunimTheme.light,
      darkTheme: uzbekCyrillic ? KunimTheme.darkSystemFont : KunimTheme.dark,
      themeMode: settings.themeMode,
      locale: settings.language.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
    );
  }
}
