import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/gen/app_localizations.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Root widget of the KUNIM app.
///
/// NOTE: `app/l10n/gen/app_localizations.dart` is produced by
/// `flutter gen-l10n` (also triggered by `flutter pub get` because
/// `flutter: generate: true` is set in `pubspec.yaml`). It does not exist
/// yet in this hand-written skeleton — see `apps/mobile/README.md`.
class KunimApp extends ConsumerWidget {
  const KunimApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      routerConfig: router,
      theme: KunimTheme.light,
      darkTheme: KunimTheme.dark,
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
    );
  }
}
