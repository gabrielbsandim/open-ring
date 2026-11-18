import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_notice.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/domain/workout_recovery.dart';

final openWorkoutStoreProvider = Provider<OpenWorkoutStore>(
  (ref) => throw UnimplementedError('Override openWorkoutStoreProvider.'),
);

final liveWorkoutRegistryProvider = Provider<LiveWorkoutRegistry>(
  (ref) => InMemoryLiveWorkoutRegistry(),
);

final workoutRecoveryLabelsProvider = Provider<WorkoutNoticeLabels>(
  (ref) => const WorkoutNoticeLabels(),
);

final workoutRecoveryProvider =
    NotifierProvider<WorkoutRecovery, RecoveredWorkout?>(WorkoutRecovery.new);

/// Closes the workouts a killed process left open, once per start; the state
/// is the newest one it closed.
class WorkoutRecovery extends Notifier<RecoveredWorkout?> {
  Future<void>? _run;

  @override
  RecoveredWorkout? build() => null;

  Future<void> run() => _run ??= _recover();

  Future<void> _recover() async {
    final store = ref.read(openWorkoutStoreProvider);
    final live = ref.read(liveWorkoutRegistryProvider);
    final now = ref.read(clockProvider)();
    RecoveredWorkout? newest;
    for (final start in await store.openStarts()) {
      if (live.isLive(start)) continue;
      newest = await store.close(start, at: now) ?? newest;
    }
    if (newest == null || !ref.mounted) return;
    state = newest;
    ref.read(dataRevisionProvider.notifier).bump();
    await _announce(newest, now);
  }

  // Only the newest gets a notice, and one that cannot post leaves the rows
  // closed all the same.
  Future<void> _announce(RecoveredWorkout workout, DateTime now) async {
    final notifier = ref.read(workoutNotifierProvider);
    final labels = ref.read(workoutRecoveryLabelsProvider);
    try {
      final units = await ref.read(unitSystemProvider.future);
      await notifier.ended(
        workoutRecoveredNoticeOf(workout, labels, units, now: now),
      );
    } on Object {
      return;
    }
  }
}
