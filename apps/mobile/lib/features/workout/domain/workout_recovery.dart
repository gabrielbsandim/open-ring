import 'package:meta/meta.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

/// A workout a killed process left open, closed at its last checkpoint.
@immutable
final class RecoveredWorkout {
  const new({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    required this.elapsed,
    required this.distanceMeters,
    required this.offsetMinutes,
  });

  final int id;
  final WorkoutType type;
  final DateTime start;
  final DateTime end;
  final Duration elapsed;
  final double? distanceMeters;
  final int offsetMinutes;
}

abstract interface class OpenWorkoutStore {
  /// The starts of the rows with no end, oldest first.
  Future<List<DateTime>> openStarts();

  /// Null when the row is gone or already has an end.
  Future<RecoveredWorkout?> close(DateTime start, {required DateTime at});
}

/// The starts a controller in this process is still recording.
abstract interface class LiveWorkoutRegistry {
  void markLive(DateTime start);

  void clear(DateTime start);

  bool isLive(DateTime start);
}

final class InMemoryLiveWorkoutRegistry implements LiveWorkoutRegistry {
  final Set<int> _live = {};

  @override
  void markLive(DateTime start) => _live.add(start.millisecondsSinceEpoch);

  @override
  void clear(DateTime start) => _live.remove(start.millisecondsSinceEpoch);

  @override
  bool isLive(DateTime start) => _live.contains(start.millisecondsSinceEpoch);
}
