import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/account/presentation/account_screen.dart';
import '../../features/ai/presentation/ai_screen.dart';
import '../../features/family/presentation/family_screen.dart';
import '../../features/goals/presentation/goal_detail_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/habits/presentation/habits_screen.dart';
import '../../features/health/presentation/health_screen.dart';
import '../../features/mood/presentation/mood_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/prayer/presentation/prayer_screen.dart';
import '../../features/quran/presentation/quran_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/social/presentation/leaderboard_screen.dart';
import '../../features/sleep/presentation/sleep_screen.dart';
import '../../features/stats/presentation/stats_screen.dart';
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

  /// The prayer screen, opened from the home tab (strip, module tile)...
  static const String prayer = '$home/$_prayer';

  /// The Qur'an: its index and, from there, the mushaf reader.
  static const String quran = '$home/$_quran';

  /// ...and from settings, so the back button returns where the user was.
  static const String settingsPrayer = '$settings/$_prayer';

  /// Notification settings, opened from settings.
  static const String settingsNotifications = '$settings/$_notifications';

  /// Daily log modules, opened from the home tab's life-area tiles.
  static const String mood = '$home/$_mood';
  static const String health = '$home/$_health';
  static const String sleep = '$home/$_sleep';
  static const String family = '$home/$_family';

  /// Personal growth: the goals list and one goal, from the home tab.
  static const String goals = '$home/$_goals';
  static String goal(String id) => '$goals/$id';

  /// All habits, from the home tab's "today's habits" section.
  static const String habits = '$home/$_habits';

  /// Friends and the global board, from the statistics tab.
  static const String leaderboard = '$stats/$_leaderboard';

  static const String _prayer = 'prayer';
  static const String _quran = 'quran';
  static const String _mood = 'mood';
  static const String _health = 'health';
  static const String _sleep = 'sleep';
  static const String _family = 'family';
  static const String _goals = 'goals';
  static const String _habits = 'habits';
  static const String _leaderboard = 'leaderboard';
  static const String _notifications = 'notifications';
  static const String _account = 'account';

  /// Sign in / account and sync, opened from settings.
  static const String settingsAccount = '$settings/$_account';
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
                routes: [
                  GoRoute(
                    path: KunimRoutes._prayer,
                    builder: (context, state) => const PrayerScreen(),
                  ),
                  GoRoute(
                    path: KunimRoutes._quran,
                    builder: (context, state) => const QuranScreen(),
                  ),
                  GoRoute(
                    path: KunimRoutes._mood,
                    builder: (context, state) => const MoodScreen(),
                  ),
                  GoRoute(
                    path: KunimRoutes._health,
                    builder: (context, state) => const HealthScreen(),
                  ),
                  GoRoute(
                    path: KunimRoutes._sleep,
                    builder: (context, state) => const SleepScreen(),
                  ),
                  GoRoute(
                    path: KunimRoutes._family,
                    builder: (context, state) => const FamilyScreen(),
                  ),
                  GoRoute(
                    path: KunimRoutes._habits,
                    builder: (context, state) => const HabitsScreen(),
                  ),
                  GoRoute(
                    path: KunimRoutes._goals,
                    builder: (context, state) => const GoalsScreen(),
                    routes: [
                      GoRoute(
                        path: ':goalId',
                        builder: (context, state) => GoalDetailScreen(
                          goalId: state.pathParameters['goalId']!,
                        ),
                      ),
                    ],
                  ),
                ],
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
                builder: (context, state) => const StatsScreen(),
                routes: [
                  GoRoute(
                    path: KunimRoutes._leaderboard,
                    builder: (context, state) => const LeaderboardScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: KunimRoutes.ai,
                builder: (context, state) => const AiScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: KunimRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: KunimRoutes._prayer,
                    builder: (context, state) => const PrayerScreen(),
                  ),
                  GoRoute(
                    path: KunimRoutes._notifications,
                    builder: (context, state) => const NotificationsScreen(),
                  ),
                  GoRoute(
                    path: KunimRoutes._account,
                    builder: (context, state) => const AccountScreen(),
                  ),
                ],
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
      // The bar has a fixed height and one-line labels; past 1.15x the labels
      // would wrap into the icons. Page content still scales fully.
      bottomNavigationBar: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: _navigationBar(l10n),
      ),
    );
  }

  Widget _navigationBar(AppLocalizations l10n) {
    return NavigationBar(
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
    );
  }
}
