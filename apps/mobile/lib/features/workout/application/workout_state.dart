import 'package:meta/meta.dart';
import 'package:open_ring/features/workout/domain/live_heart_rate_source.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';

enum WorkoutSave { none, saving, saved, failed }

@immutable
final class WorkoutState {
  const new({
    this.snapshot,
    this.save = WorkoutSave.none,
    this.workoutId,
    this.heartRateProblem,
    this.heartRateStalled = false,
    this.locationProblem,
  });

  final WorkoutSnapshot? snapshot;
  final WorkoutSave save;
  final int? workoutId;
  final HeartRateProblem? heartRateProblem;
  final bool heartRateStalled;
  final LocationProblem? locationProblem;

  WorkoutStatus get status => snapshot?.status ?? WorkoutStatus.idle;

  bool get live => switch (status) {
    WorkoutStatus.running || WorkoutStatus.paused => true,
    WorkoutStatus.idle ||
    WorkoutStatus.finished ||
    WorkoutStatus.discarded => false,
  };

  WorkoutState next({
    WorkoutSnapshot? snapshot,
    WorkoutSave? save,
    int? workoutId,
    HeartRateProblem? heartRateProblem,
    bool? heartRateStalled,
    LocationProblem? locationProblem,
  }) => WorkoutState(
    snapshot: snapshot ?? this.snapshot,
    save: save ?? this.save,
    workoutId: workoutId ?? this.workoutId,
    heartRateProblem: heartRateProblem ?? this.heartRateProblem,
    heartRateStalled: heartRateStalled ?? this.heartRateStalled,
    locationProblem: locationProblem ?? this.locationProblem,
  );

  WorkoutState withHeartRateRestarted() => WorkoutState(
    snapshot: snapshot,
    save: save,
    workoutId: workoutId,
    locationProblem: locationProblem,
  );

  WorkoutState withLocationRestarted() => WorkoutState(
    snapshot: snapshot,
    save: save,
    workoutId: workoutId,
    heartRateProblem: heartRateProblem,
    heartRateStalled: heartRateStalled,
  );
}
