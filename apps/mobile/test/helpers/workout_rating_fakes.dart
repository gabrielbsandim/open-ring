import 'dart:async';

import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_rating_store.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

final class MemoryRatings implements WorkoutRatingStore, WorkoutHistoryReader {
  new({
    Iterable<SavedWorkout> saved = const [],
    Iterable<ImportedWorkout> imported = const [],
  }) {
    for (final workout in saved) {
      _saved[workout.id] = workout;
    }
    for (final workout in imported) {
      _imported[workout.recordId] = workout;
    }
  }

  final _saved = <int, SavedWorkout>{};
  final _imported = <String, ImportedWorkout>{};
  final recorded = <(int, int?)>[];
  final importedWrites = <(String, int?)>[];
  Error? failure;
  Completer<void>? hold;

  int? ratingOfSaved(int id) => _saved[id]?.rating;

  int? ratingOfImported(String recordId) => _imported[recordId]?.rating;

  @override
  Future<bool> rateRecorded(int id, int? rating) async {
    recorded.add((id, rating));
    await hold?.future;
    final error = failure;
    if (error != null) throw error;
    final current = _saved[id];
    if (current == null) return false;
    _saved[id] = SavedWorkout(
      id: current.id,
      workout: current.workout,
      utcOffset: current.utcOffset,
      health: current.health,
      rating: rating,
    );
    return true;
  }

  @override
  Future<bool> rateImported(String recordId, int? rating) async {
    importedWrites.add((recordId, rating));
    await hold?.future;
    final error = failure;
    if (error != null) throw error;
    final current = _imported[recordId];
    if (current == null) return false;
    _imported[recordId] = ImportedWorkout(
      recordId: current.recordId,
      source: current.source,
      type: current.type,
      start: current.start,
      end: current.end,
      utcOffset: current.utcOffset,
      rating: rating,
    );
    return true;
  }

  @override
  Future<SavedWorkout?> byId(int id) async => _saved[id];

  Future<ImportedWorkout?> importedById(String recordId) async =>
      _imported[recordId];

  @override
  Future<List<WorkoutListItem>> recent({required int limit}) async => const [];

  @override
  Future<List<WorkoutListItem>> intersecting({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<List<SavedWorkout>> routed({
    required DateTime from,
    required DateTime to,
    required Set<WorkoutType> types,
  }) async => const [];
}

final class ImportedRatings implements ImportedWorkoutReader {
  const new(this._ratings);

  final MemoryRatings _ratings;

  @override
  Future<ImportedWorkouts> recent({required int limit}) async =>
      (priority: const [ringSource], workouts: const <ImportedWorkout>[]);

  @override
  Future<ImportedWorkout?> byRecordId(String recordId) =>
      _ratings.importedById(recordId);

  @override
  Future<ImportedWorkouts> intersecting({
    required DateTime from,
    required DateTime to,
  }) async =>
      (priority: const [ringSource], workouts: const <ImportedWorkout>[]);
}
