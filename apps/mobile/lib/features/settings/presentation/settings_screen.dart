import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../../account/presentation/account_screen.dart';
import '../../notifications/application/notification_providers.dart';
import '../../prayer/application/prayer_providers.dart';
import '../../prayer/presentation/prayer_labels.dart';

/// Settings. Language, theme, prayer and notification settings work and are
/// saved on the device; sections that are not built yet show a coming-soon
/// badge and do not react to taps.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider);
    final prayerCity = ref.watch(prayerSettingsProvider).value?.city;
    final remindersOn =
        ref.watch(prayerReminderSettingsProvider).value?.enabled ?? false;

    return KunimStatusBarRegion(
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(KunimSpacing.lg),
            children: [
              ScreenIntro(
                eyebrow: l10n.appTitle,
                title: l10n.navSettings,
                subtitle: l10n.settingsSubtitle,
              ),
              const SizedBox(height: KunimSpacing.xl),
              const _ProfileCard(),
              const SizedBox(height: KunimSpacing.xl),
              _SettingTile(
                icon: Icons.language_rounded,
                title: l10n.settingsLanguage,
                subtitle: languageName(l10n, settings.language),
                onTap: () => _pickLanguage(context, ref, settings.language),
              ),
              _SettingTile(
                icon: Icons.dark_mode_outlined,
                title: l10n.settingsAppearance,
                subtitle: _themeName(l10n, settings.themeMode),
                onTap: () => _pickTheme(context, ref, settings.themeMode),
              ),
              _SettingTile(
                icon: Icons.location_on_outlined,
                title: l10n.settingsPrayer,
                subtitle: prayerCity == null
                    ? l10n.prayerPending
                    : PrayerLabels.city(l10n, prayerCity),
                onTap: () => context.go(KunimRoutes.settingsPrayer),
              ),
              _SettingTile(
                icon: Icons.notifications_none_rounded,
                title: l10n.settingsNotifications,
                subtitle:
                    remindersOn ? l10n.notifPrayerOn : l10n.notifPrayerOff,
                onTap: () => context.go(KunimRoutes.settingsNotifications),
              ),
              _SettingTile(
                icon: Icons.shield_outlined,
                title: l10n.settingsPrivacy,
                subtitle: l10n.settingsPrivacyMeta,
              ),
              const SizedBox(height: KunimSpacing.lg),
              HeritageCard(
                child: Text(
                  l10n.settingsVersion,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String languageName(AppLocalizations l10n, AppLanguage language) {
    return switch (language) {
      AppLanguage.uz => l10n.languageNameUz,
      AppLanguage.uzCyrl => l10n.languageNameUzCyrl,
      AppLanguage.ru => l10n.languageNameRu,
      AppLanguage.en => l10n.languageNameEn,
    };
  }

  static String _themeName(AppLocalizations l10n, ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => l10n.themeSystem,
      ThemeMode.light => l10n.themeLight,
      ThemeMode.dark => l10n.themeDark,
    };
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    AppLanguage current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showKunimChoiceSheet<AppLanguage>(
      context: context,
      title: l10n.onbLanguageTitle,
      selected: current,
      options: [
        for (final language in AppLanguage.values)
          (language, languageName(l10n, language)),
      ],
    );
    if (picked != null) {
      await ref.read(appSettingsProvider.notifier).setLanguage(picked);
    }
  }

  Future<void> _pickTheme(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showKunimChoiceSheet<ThemeMode>(
      context: context,
      title: l10n.settingsTheme,
      selected: current,
      options: [
        (ThemeMode.system, l10n.themeSystem),
        (ThemeMode.light, l10n.themeLight),
        (ThemeMode.dark, l10n.themeDark),
      ],
    );
    if (picked != null) {
      await ref.read(appSettingsProvider.notifier).setThemeMode(picked);
    }
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authControllerProvider);
    final signedIn = auth is AuthSignedIn ? auth : null;
    final expired = auth is AuthSignedOut && auth.sessionExpired;
    final subtitle = signedIn != null
        ? syncStatusLabel(context, ref.watch(syncStatusProvider))
        : expired
            ? l10n.authErrorSessionExpired
            : l10n.settingsLocalOnly;

    return Container(
      padding: const EdgeInsets.all(KunimSpacing.lg),
      decoration: BoxDecoration(
        color: KunimColors.ink,
        borderRadius: BorderRadius.circular(KunimRadii.extraLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: KunimColors.goldSoft,
                child: Icon(
                  signedIn != null
                      ? Icons.cloud_done_outlined
                      : Icons.person_outline_rounded,
                  color: KunimColors.ink,
                ),
              ),
              const SizedBox(width: KunimSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signedIn?.email ?? l10n.settingsGuestName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                          ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFFB7C2C2)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: KunimSpacing.md),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KunimColors.goldSoft,
              foregroundColor: KunimColors.ink,
            ),
            onPressed: () => context.go(KunimRoutes.settingsAccount),
            child: Text(
              signedIn != null ? l10n.settingsAccount : l10n.authSignInButton,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// `null` means the section is not built yet: no ripple, no chevron, and a
  /// coming-soon badge instead.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: KunimSpacing.sm),
      child: HeritageCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: KunimSpacing.lg,
          vertical: KunimSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: KunimSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  if (subtitle != null)
                    Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: KunimSpacing.sm),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded)
            else
              const ComingSoonBadge(),
          ],
        ),
      ),
    );
  }
}
