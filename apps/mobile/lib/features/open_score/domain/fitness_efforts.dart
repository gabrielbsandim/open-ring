import 'package:metrics/metrics.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

const Set<WorkoutType> fitnessTypes = {
  WorkoutType.running,
  WorkoutType.walking,
};
const fitnessMinSamplesPerMinute = 1;

FitnessGait? fitnessGaitOf(WorkoutType type) => switch (type) {
  WorkoutType.running => FitnessGait.run,
  WorkoutType.walking => FitnessGait.walk,
  _ => null,
};

/// The pause free stretches of a recorded outdoor run or walk, each without
/// its first minutes, or null for a workout no estimate can come from.
FitnessEffort? fitnessEffortOf(SavedWorkout saved) {
  final workout = saved.workout;
  final gait = fitnessGaitOf(workout.type);
  if (gait == null) return null;
  final stretches = [
    for (final segment in workout.route.segments)
      ?_stretch(segment, workout.heartRate),
  ];
  if (stretches.isEmpty) return null;
  return (
    date: LocalDate.fromInstant(workout.start, saved.utcOffset),
    gait: gait,
    stretches: stretches,
  );
}

FitnessStretch? _stretch(List<TrackPoint> segment, List<BpmSample> heartRate) {
  if (segment.isEmpty) return null;
  final from = segment.first.at.add(fitnessWarmUp);
  final points = [
    for (final point in segment)
      if (!point.at.isBefore(from)) point,
  ];
  if (points.length < 2) return null;
  final start = points.first.at;
  final end = points.last.at;
  final beats = [
    for (final sample in heartRate)
      if (!sample.at.isBefore(start) && !sample.at.isAfter(end)) sample.bpm,
  ];
  final duration = end.difference(start);
  if (beats.isEmpty) return null;
  if (beats.length < duration.inMinutes * fitnessMinSamplesPerMinute) {
    return null;
  }
  var meters = 0.0;
  for (var i = 1; i < points.length; i++) {
    meters += haversineMeters(points[i - 1], points[i]);
  }
  return (
    duration: duration,
    meters: meters,
    meanBpm: beats.reduce((a, b) => a + b) / beats.length,
  );
}
