import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/export/application/export_controller.dart';
import 'package:open_ring/features/export/application/export_providers.dart';
import 'package:open_ring/features/export/domain/data_exporter.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_source_selection.dart';
import 'package:open_ring/features/workout/domain/workout_analysis.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';

const recentWorkoutLimit = 5;

final workoutHistoryReaderProvider = Provider<WorkoutHistoryReader>(
  (ref) => const EmptyWorkoutHistoryReader(),
);

final importedWorkoutReaderProvider = Provider<ImportedWorkoutReader>(
  (ref) => const NoImportedWorkoutReader(),
);

final recentWorkoutsProvider = FutureProvider<List<WorkoutEntry>>((ref) async {
  ref.watch(dataRevisionProvider);
  final (own, imported) = await (
    ref.watch(workoutHistoryReaderProvider).recent(limit: recentWorkoutLimit),
    ref.watch(importedWorkoutReaderProvider).recent(limit: recentWorkoutLimit),
  ).wait;
  final selected = selectWorkouts([
    ...own,
    ...imported.workouts,
  ], imported.priority);
  return selected.take(recentWorkoutLimit).toList();
});

final FutureProviderFamily<ImportedWorkout?, String> importedWorkoutProvider =
    FutureProvider.family<ImportedWorkout?, String>((ref, recordId) {
      ref.watch(dataRevisionProvider);
      return ref.watch(importedWorkoutReaderProvider).byRecordId(recordId);
    });

// The newest row of the recent list, so an overlap hides the same workout
// here as in the history.
final lastWorkoutProvider = FutureProvider<WorkoutEntry?>((ref) async {
  final recent = await ref.watch(recentWorkoutsProvider.future);
  return recent.firstOrNull;
});

final FutureProviderFamily<SavedWorkout?, int> savedWorkoutProvider =
    FutureProvider.family<SavedWorkout?, int>((ref, id) {
      ref.watch(dataRevisionProvider);
      return ref.watch(workoutHistoryReaderProvider).byId(id);
    });

final savedWorkoutZonesProvider = Provider<HeartRateZones?>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  final year = ref.watch(clockProvider)().year;
  return workoutProfileOf(profile, year: year).zones;
});

Future<bool> deleteWorkout(WidgetRef ref, int id) async {
  final deleted = await ref.read(workoutStoreProvider).delete(id);
  ref.read(workoutProvider.notifier).forgetSaved(id);
  ref.read(dataRevisionProvider.notifier).bump();
  return deleted;
}

Future<void> shareWorkoutGpx(WidgetRef ref, FinishedWorkout workout) async {
  final file = await ref
      .read(dataExporterProvider)
      .exportRoute(gpxRouteOf(workout));
  await _share(ref, file);
}

Future<void> shareWorkoutCsv(
  WidgetRef ref,
  FinishedWorkout workout, {
  required Duration offset,
}) async {
  final file = await ref
      .read(dataExporterProvider)
      .exportWorkoutCsv(workout, offset: offset);
  await _share(ref, file);
}

Future<void> _share(WidgetRef ref, ExportFile file) =>
    ref.read(fileSharerProvider).share([file], subject: exportFileName(file));
