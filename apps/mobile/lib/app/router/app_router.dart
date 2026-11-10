import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/tabs_shell.dart';
import 'package:open_ring/features/activity/presentation/activity_screen.dart';
import 'package:open_ring/features/heart/presentation/heart_screen.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/sleep/presentation/sleep_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppTab.today.path,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => TabsShell(navigationShell: shell),
        branches: [
          for (final tab in AppTab.values)
            StatefulShellBranch(routes: [_tabRoute(tab)]),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

GoRoute _tabRoute(AppTab tab) => switch (tab) {
  AppTab.today => GoRoute(
    path: tab.path,
    builder: (_, _) => const TodayScreen(),
  ),
  AppTab.sleep => GoRoute(
    path: tab.path,
    builder: (_, _) => const SleepScreen(),
  ),
  AppTab.heart => GoRoute(
    path: tab.path,
    builder: (_, _) => const HeartScreen(),
  ),
  AppTab.activity => GoRoute(
    path: tab.path,
    builder: (_, _) => const ActivityScreen(),
  ),
  AppTab.ring => GoRoute(
    path: tab.path,
    builder: (_, _) => const RingScreen(),
    routes: [
      GoRoute(path: 'settings', builder: (_, _) => const SettingsScreen()),
    ],
  ),
};
