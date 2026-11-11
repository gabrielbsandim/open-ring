import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/tabs_shell.dart';
import 'package:open_ring/features/activity/presentation/activity_screen.dart';
import 'package:open_ring/features/heart/presentation/heart_screen.dart';
import 'package:open_ring/features/heart/presentation/measure_screen.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/presentation/first_sync_screen.dart';
import 'package:open_ring/features/onboarding/presentation/health_permission_screen.dart';
import 'package:open_ring/features/onboarding/presentation/permissions_screen.dart';
import 'package:open_ring/features/onboarding/presentation/profile_screen.dart';
import 'package:open_ring/features/onboarding/presentation/welcome_screen.dart';
import 'package:open_ring/features/ring/presentation/pair_error_screen.dart';
import 'package:open_ring/features/ring/presentation/pair_screen.dart';
import 'package:open_ring/features/ring/presentation/protocol_lab_screen.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/presentation/privacy_policy_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_routes.dart';
import 'package:open_ring/features/sleep/presentation/sleep_screen.dart';
import 'package:open_ring/features/today/presentation/formula_screen.dart';
import 'package:open_ring/features/today/presentation/readiness_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:open_ring/features/trends/presentation/trends_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppTab.today.path,
    redirect: (_, state) => onboardingRedirect(
      completed: ref.read(onboardingProvider),
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: AppPaths.privacy,
        builder: (_, _) => const PrivacyPolicyScreen(),
      ),
      _onboardingRoute(),
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

// Until a ring is paired every location leads to onboarding; afterwards the
// onboarding routes stay reachable so the first sync can finish there.
String? onboardingRedirect({
  required bool completed,
  required String location,
}) {
  if (completed) return null;
  // Health Connect links here while onboarding asks for its permissions.
  if (location == AppPaths.privacy) return null;
  if (location.startsWith(AppPaths.onboarding)) return null;
  return AppPaths.onboarding;
}

GoRoute _onboardingRoute() => GoRoute(
  path: AppPaths.onboarding,
  builder: (_, _) => const WelcomeScreen(),
  routes: [
    GoRoute(path: 'permissions', builder: (_, _) => const PermissionsScreen()),
    GoRoute(path: 'profile', builder: (_, _) => const ProfileScreen()),
    GoRoute(path: 'health', builder: (_, _) => const HealthPermissionScreen()),
    _pairRoute(PairFlow.onboarding),
  ],
);

GoRoute _pairRoute(PairFlow flow) => GoRoute(
  path: 'pair',
  builder: (_, _) => PairScreen(flow: flow),
  routes: [
    GoRoute(
      path: 'error/:reason',
      builder: (_, state) => PairErrorScreen(
        flow: flow,
        failure: PairErrorScreen.parse(state.pathParameters['reason']),
      ),
    ),
    GoRoute(path: 'sync', builder: (_, _) => const FirstSyncScreen()),
  ],
);

GoRoute _formulaRoute() =>
    GoRoute(path: 'formula', builder: (_, _) => const FormulaScreen());

GoRoute _tabRoute(AppTab tab) => switch (tab) {
  AppTab.today => GoRoute(
    path: tab.path,
    builder: (_, _) => const TodayScreen(),
    routes: [
      GoRoute(
        path: 'readiness',
        builder: (_, _) => const ReadinessScreen(),
        routes: [_formulaRoute()],
      ),
    ],
  ),
  AppTab.sleep => GoRoute(
    path: tab.path,
    builder: (_, _) => const SleepScreen(),
    routes: [_formulaRoute()],
  ),
  AppTab.heart => GoRoute(
    path: tab.path,
    builder: (_, _) => const HeartScreen(),
    routes: [
      GoRoute(path: 'measure', builder: (_, _) => const MeasureScreen()),
      GoRoute(path: 'trends', builder: (_, _) => const TrendsScreen()),
    ],
  ),
  AppTab.activity => GoRoute(
    path: tab.path,
    builder: (_, _) => const ActivityScreen(),
    routes: workoutRoutes(),
  ),
  AppTab.ring => GoRoute(
    path: tab.path,
    builder: (_, _) => const RingScreen(),
    routes: [
      settingsRoute(),
      _pairRoute(PairFlow.ring),
      if (kDebugMode)
        GoRoute(path: 'lab', builder: (_, _) => const ProtocolLabScreen()),
    ],
  ),
};
