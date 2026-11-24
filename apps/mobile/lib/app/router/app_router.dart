import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/tabs_shell.dart';
import 'package:open_ring/features/activity/presentation/activity_screen.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/presentation/ai_context_preview_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_readings_screen.dart';
import 'package:open_ring/features/body/presentation/body_screen.dart';
import 'package:open_ring/features/effort/presentation/effort_formula_screen.dart';
import 'package:open_ring/features/effort/presentation/effort_screen.dart';
import 'package:open_ring/features/energy/presentation/energy_formula_screen.dart';
import 'package:open_ring/features/energy/presentation/energy_screen.dart';
import 'package:open_ring/features/food/presentation/food_comparison_detail_screen.dart';
import 'package:open_ring/features/food/presentation/food_comparisons_screen.dart';
import 'package:open_ring/features/food/presentation/food_day_screen.dart';
import 'package:open_ring/features/food/presentation/food_formula_screen.dart';
import 'package:open_ring/features/food/presentation/food_gallery_screen.dart';
import 'package:open_ring/features/food/presentation/food_meal_screen.dart';
import 'package:open_ring/features/food/presentation/food_plate_screen.dart';
import 'package:open_ring/features/food/presentation/food_week_screen.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/presentation/goal_end_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_formula_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_pick_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_refusal_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_review_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_screening_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_setup_screen.dart';
import 'package:open_ring/features/heart/presentation/heart_screen.dart';
import 'package:open_ring/features/heart/presentation/measure_screen.dart';
import 'package:open_ring/features/modules/presentation/modules_offer_screen.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/presentation/first_sync_screen.dart';
import 'package:open_ring/features/onboarding/presentation/health_permission_screen.dart';
import 'package:open_ring/features/onboarding/presentation/permissions_screen.dart';
import 'package:open_ring/features/onboarding/presentation/profile_screen.dart';
import 'package:open_ring/features/onboarding/presentation/welcome_screen.dart';
import 'package:open_ring/features/open_score/presentation/day_score_formula_screen.dart';
import 'package:open_ring/features/open_score/presentation/day_score_history_screen.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/features/open_score/presentation/level_screen.dart';
import 'package:open_ring/features/open_score/presentation/overall_screen.dart';
import 'package:open_ring/features/open_score/presentation/overall_weeks_screen.dart';
import 'package:open_ring/features/ring/presentation/pair_error_screen.dart';
import 'package:open_ring/features/ring/presentation/pair_screen.dart';
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

// Until onboarding ends, with or without a ring, every location leads to it;
// afterwards its routes stay reachable so the first sync can finish there.
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
    GoRoute(path: 'modules', builder: (_, _) => const ModulesOfferScreen()),
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
    GoRoute(
      path: 'sync',
      builder: (_, _) => FirstSyncScreen(flow: flow),
    ),
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
      GoRoute(path: 'body', builder: (_, _) => const BodyScreen()),
      GoRoute(
        path: 'effort',
        builder: (_, _) => const EffortScreen(),
        routes: [
          GoRoute(
            path: 'formula',
            builder: (_, _) => const EffortFormulaScreen(),
          ),
        ],
      ),
      GoRoute(
        path: 'energy',
        builder: (_, _) => const EnergyScreen(),
        routes: [
          GoRoute(
            path: 'formula',
            builder: (_, _) => const EnergyFormulaScreen(),
          ),
        ],
      ),
      GoRoute(
        path: 'food',
        builder: (_, _) => const FoodDayScreen(),
        routes: [
          GoRoute(path: 'week', builder: (_, _) => const FoodWeekScreen()),
          GoRoute(path: 'plate', builder: (_, _) => const FoodPlateScreen()),
          GoRoute(
            path: 'formula',
            builder: (_, _) => const FoodFormulaScreen(),
          ),
          GoRoute(
            path: 'comparisons',
            builder: (_, _) => const FoodComparisonsScreen(),
            routes: [
              GoRoute(
                path: ':link',
                builder: (_, state) => FoodComparisonDetailScreen(
                  link: FoodLink.values
                      .asNameMap()[state.pathParameters['link']],
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'gallery',
            builder: (_, state) => FoodGalleryScreen(
              initialDay: LocalDate.tryParse(state.uri.queryParameters['day']),
            ),
          ),
          GoRoute(
            path: 'meal/:id',
            builder: (_, state) => FoodMealScreen(
              mealId: int.tryParse(state.pathParameters['id'] ?? ''),
            ),
          ),
        ],
      ),
      GoRoute(path: 'goals', builder: (_, _) => const GoalScreen()),
      GoRoute(
        path: 'goals/pick',
        builder: (_, state) => GoalPickScreen(
          initial: GoalKind.values
              .asNameMap()[state.uri.queryParameters['goal']],
        ),
      ),
      GoRoute(
        path: 'goals/screening',
        builder: (_, _) => const GoalScreeningScreen(),
      ),
      GoRoute(path: 'goals/setup', builder: (_, _) => const GoalSetupScreen()),
      GoRoute(
        path: 'goals/review',
        builder: (_, _) => const GoalReviewScreen(),
      ),
      GoRoute(
        path: 'goals/formula',
        builder: (_, _) => const GoalFormulaScreen(),
      ),
      GoRoute(path: 'goals/end', builder: (_, _) => const GoalEndScreen()),
      GoRoute(
        path: 'goals/pregnancy',
        builder: (_, _) => const GoalRefusalScreen.pregnancy(),
      ),
      GoRoute(
        path: 'goals/refused/:block',
        builder: (_, state) => GoalRefusalScreen(
          block: IntakeBlock.values.asNameMap()[state.pathParameters['block']],
        ),
      ),
      GoRoute(
        path: 'day-score',
        builder: (_, state) => DayScoreReceiptScreen(
          day: LocalDate.tryParse(state.uri.queryParameters['day']),
        ),
        routes: [
          GoRoute(
            path: 'formula',
            builder: (_, _) => const DayScoreFormulaScreen(),
          ),
          GoRoute(
            path: 'history',
            builder: (_, _) => const DayScoreHistoryScreen(),
          ),
          GoRoute(path: 'level', builder: (_, _) => const LevelScreen()),
          GoRoute(
            path: 'overall',
            builder: (_, _) => const OverallScreen(),
            routes: [
              GoRoute(
                path: 'weeks',
                builder: (_, _) => const OverallWeeksScreen(),
              ),
            ],
          ),
        ],
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
      GoRoute(
        path: 'trends',
        builder: (_, _) => const TrendsScreen(),
        routes: [
          GoRoute(
            path: 'ai',
            builder: (_, _) => const AiReadingsScreen(),
            routes: [
              GoRoute(
                path: 'preview',
                builder: (_, state) => AiContextPreviewScreen(
                  kind: state.uri.queryParameters['kind'],
                  report: switch (state.extra) {
                    final AiReport report => report,
                    _ => null,
                  },
                ),
              ),
            ],
          ),
        ],
      ),
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
    routes: [settingsRoute(), _pairRoute(PairFlow.ring)],
  ),
};
