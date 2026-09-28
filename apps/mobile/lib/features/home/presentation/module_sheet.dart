/// "All sections": the life areas that are not a widget of their own.
///
/// The home grid is the user's own widgets now, so this sheet is what keeps
/// every screen reachable — a widget links to its area (see
/// `habitKindRoute`), and the areas nobody made a widget for live here.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/tokens.dart';

class KunimModule {
  const KunimModule({
    required this.title,
    required this.meta,
    required this.icon,
    required this.color,
    this.route,
  });

  final String title;
  final String meta;
  final IconData icon;
  final Color color;

  /// `null` while the section has no screen yet.
  final String? route;
}

List<KunimModule> kunimModules(AppLocalizations l10n) => [
      KunimModule(
        title: l10n.modulePrayer,
        meta: l10n.modulePrayerMeta,
        icon: Icons.mosque_outlined,
        color: KunimModuleColors.prayer,
        route: KunimRoutes.prayer,
      ),
      KunimModule(
        title: l10n.moduleQuran,
        meta: l10n.moduleQuranMeta,
        icon: Icons.menu_book_rounded,
        color: KunimModuleColors.quran,
      ),
      KunimModule(
        title: l10n.moduleMood,
        meta: l10n.moduleMoodMeta,
        icon: Icons.spa_outlined,
        color: KunimModuleColors.mood,
        route: KunimRoutes.mood,
      ),
      KunimModule(
        title: l10n.moduleFamily,
        meta: l10n.moduleFamilyMeta,
        icon: Icons.favorite_outline_rounded,
        color: KunimModuleColors.family,
        route: KunimRoutes.family,
      ),
      KunimModule(
        title: l10n.moduleHealth,
        meta: l10n.moduleHealthMeta,
        icon: Icons.fitness_center_rounded,
        color: KunimModuleColors.health,
        route: KunimRoutes.health,
      ),
      KunimModule(
        title: l10n.moduleWork,
        meta: l10n.moduleWorkMeta,
        icon: Icons.work_outline_rounded,
        color: KunimModuleColors.work,
        route: KunimRoutes.day,
      ),
      KunimModule(
        title: l10n.moduleGrowth,
        meta: l10n.moduleGrowthMeta,
        icon: Icons.track_changes_rounded,
        color: KunimModuleColors.mood,
        route: KunimRoutes.goals,
      ),
      KunimModule(
        title: l10n.moduleSleep,
        meta: l10n.moduleSleepMeta,
        icon: Icons.dark_mode_outlined,
        color: KunimModuleColors.sleep,
        route: KunimRoutes.sleep,
      ),
    ];

Future<void> showModuleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const ModuleSheet(),
  );
}

class ModuleSheet extends StatelessWidget {
  const ModuleSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KunimSpacing.lg,
          0,
          KunimSpacing.lg,
          KunimSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.homeAllModules, style: theme.textTheme.titleLarge),
            const SizedBox(height: KunimSpacing.sm),
            for (final module in kunimModules(l10n))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: module.color,
                  child: Icon(module.icon, color: Colors.white, size: 20),
                ),
                title: Text(module.title),
                subtitle: Text(module.meta),
                trailing: const Icon(Icons.chevron_right_rounded),
                // Captured before the pop: this sheet's own context is
                // gone by the time the navigation runs.
                onTap: () {
                  final route = module.route;
                  final router = GoRouter.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  final soon = l10n.moduleComingSoon(module.title);
                  Navigator.of(context).pop();
                  if (route != null) {
                    router.go(route);
                  } else {
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(soon)));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
