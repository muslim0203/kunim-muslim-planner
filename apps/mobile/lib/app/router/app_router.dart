import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/tasks/presentation/tasks_screen.dart';
import '../l10n/gen/app_localizations.dart';

/// Top-level route paths. Keep these as constants so features and deep
/// links (notification taps, etc.) never hand-type a path string.
abstract final class KunimRoutes {
  static const String home = '/home';
  static const String day = '/day';
  static const String stats = '/stats';
  static const String ai = '/ai';
  static const String settings = '/settings';
}

/// The app's [GoRouter], exposed as a provider so features can `ref.read`
/// it (e.g. for programmatic navigation) instead of reaching for a global.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: KunimRoutes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return _KunimScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: KunimRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: KunimRoutes.day,
                builder: (context, state) => const TasksScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: KunimRoutes.stats,
                builder: (context, state) => const _StatsPlaceholderScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: KunimRoutes.ai,
                builder: (context, state) => const _AiPlaceholderScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: KunimRoutes.settings,
                builder: (context, state) => const _SettingsPlaceholderScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Scaffold shared by all five bottom-nav branches. Labels come from
/// [AppLocalizations] only — no hardcoded UI strings.
class _KunimScaffoldWithNavBar extends StatelessWidget {
  const _KunimScaffoldWithNavBar({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: l10n.navDay,
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart),
            label: l10n.navStats,
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome),
            label: l10n.navAi,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}

/// Phase-0 placeholder: each branch will be replaced by its real feature
/// screen under `lib/features/<name>/presentation/` in later phases.
class _StatsPlaceholderScreen extends StatelessWidget {
  const _StatsPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navStats)),
      body: Center(child: Text(l10n.navStats)),
    );
  }
}

class _AiPlaceholderScreen extends StatelessWidget {
  const _AiPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navAi)),
      body: Center(child: Text(l10n.navAi)),
    );
  }
}

class _SettingsPlaceholderScreen extends StatelessWidget {
  const _SettingsPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: Center(child: Text(l10n.navSettings)),
    );
  }
}
