import 'package:meta/meta.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

enum WorkoutHealthStatus { notQueued, pending, sent, failed }

sealed class WorkoutEntry {
  const new();

  WorkoutType get type;
  DateTime get start;
  DateTime get end;
  Duration get utcOffset;
  Duration get elapsed;
  String get source;

  bool overlaps(WorkoutEntry other) =>
      start.isBefore(other.end) && other.start.isBefore(end);
}

@immutable
final class WorkoutListItem extends WorkoutEntry {
  const new({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    required this.utcOffset,
    required this.elapsed,
    this.distanceMeters,
    this.averageHeartRate,
    this.activeKilocalories,
    this.health = WorkoutHealthStatus.notQueued,
  });

  final int id;
  @override
  final WorkoutType type;
  @override
  final DateTime start;
  @override
  final DateTime end;
  @override
  final Duration utcOffset;
  @override
  final Duration elapsed;
  final double? distanceMeters;
  final int? averageHeartRate;
  final double? activeKilocalories;
  final WorkoutHealthStatus health;

  @override
  String get source => ringSource;
}

// A workout another app wrote to the health platform. Only its type and
// time are read, so it carries no heart rate, distance or route.
@immutable
final class ImportedWorkout extends WorkoutEntry {
  const new({
    required this.recordId,
    required this.source,
    required this.type,
    required this.start,
    required this.end,
    required this.utcOffset,
  });

  final String recordId;
  @override
  final String source;
  @override
  final WorkoutType type;
  @override
  final DateTime start;
  @override
  final DateTime end;
  @override
  final Duration utcOffset;

  @override
  Duration get elapsed => end.difference(start);
}

@immutable
final class SavedWorkout {
  const new({
    required this.id,
    required this.workout,
    required this.utcOffset,
    this.health = WorkoutHealthStatus.notQueued,
  });

  final int id;
  final FinishedWorkout workout;
  final Duration utcOffset;
  final WorkoutHealthStatus health;
}

abstract interface class WorkoutHistoryReader {
  Future<List<WorkoutListItem>> recent({required int limit});

  Future<SavedWorkout?> byId(int id);
}

final class EmptyWorkoutHistoryReader implements WorkoutHistoryReader {
  const new();

  @override
  Future<List<WorkoutListItem>> recent({required int limit}) async => const [];

  @override
  Future<SavedWorkout?> byId(int id) async => null;
}

typedef ImportedWorkouts = ({
  List<String> priority,
  List<ImportedWorkout> workouts,
});

const ImportedWorkouts noImportedWorkouts = (
  priority: [ringSource],
  workouts: [],
);

abstract interface class ImportedWorkoutReader {
  // The newest workouts other apps wrote and the order that picks among
  // overlapping ones; when reading is off the order holds OpenRing only.
  Future<ImportedWorkouts> recent({required int limit});

  Future<ImportedWorkout?> byRecordId(String recordId);
}

final class NoImportedWorkoutReader implements ImportedWorkoutReader {
  const new();

  @override
  Future<ImportedWorkouts> recent({required int limit}) async =>
      noImportedWorkouts;

  @override
  Future<ImportedWorkout?> byRecordId(String recordId) async => null;
}
