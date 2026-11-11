import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/imported_workout_screen.dart';
import 'package:open_ring/features/workout/presentation/live_workout_screen.dart';
import 'package:open_ring/features/workout/presentation/location_permission_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/features/workout/presentation/workout_pick_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_summary_screen.dart';

List<RouteBase> workoutRoutes() => [
  GoRoute(
    path: 'workout',
    builder: (_, _) => const WorkoutPickScreen(),
    routes: [
      GoRoute(
        path: 'location',
        builder: (_, state) => LocationPermissionScreen(
          type: WorkoutTypeLabels.parse(state.uri.queryParameters['type']),
        ),
      ),
    ],
  ),
  GoRoute(path: 'live-workout', builder: (_, _) => const LiveWorkoutScreen()),
  GoRoute(
    path: 'workout-summary',
    builder: (_, _) => const WorkoutSummaryScreen(),
    routes: [
      GoRoute(
        path: ':id',
        builder: (_, state) => WorkoutSummaryScreen(
          workoutId: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
        ),
      ),
    ],
  ),
  GoRoute(
    path: 'imported-workout/:recordId',
    builder: (_, state) =>
        ImportedWorkoutScreen(recordId: state.pathParameters['recordId'] ?? ''),
  ),
];

String workoutSummaryPath(int id) => '${AppPaths.workoutSummary}/$id';

String importedWorkoutPath(String recordId) =>
    '${AppPaths.importedWorkout}/${Uri.encodeComponent(recordId)}';

String workoutLocationPath(WorkoutType type) => Uri(
  path: AppPaths.workoutLocation,
  queryParameters: {'type': type.name},
).toString();

Future<void> beginWorkout(
  WidgetRef ref,
  GoRouter router,
  WorkoutType type, {
  required LocationNotice notice,
  bool? gps,
}) async {
  await ref
      .read(workoutProvider.notifier)
      .start(type, notice: notice, gps: gps);
  router.go(AppPaths.workoutLive);
}
