import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/workout/domain/workout_analysis.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/workouts_dao.dart';

final class DriftWorkoutHistoryReader implements WorkoutHistoryReader {
  new(AppDatabase db) : _dao = WorkoutsDao(db);

  final WorkoutsDao _dao;

  @override
  Future<List<WorkoutListItem>> recent({required int limit}) async {
    if (limit <= 0) return const [];
    final rows = await _dao.newestFinished(limit: limit);
    final statuses = await _dao.outboxStatusOf(rows.map((r) => r.startUtcMs));
    return [
      for (final row in rows)
        if (row.endUtcMs case final end?)
          WorkoutListItem(
            id: row.id,
            type: WorkoutType.ofActivityType(row.activityType),
            start: fromUtcMs(row.startUtcMs),
            end: fromUtcMs(end),
            utcOffset: offsetOf(row.offsetMinutes),
            elapsed: _elapsed(row, end),
            distanceMeters: row.distanceMeters,
            averageHeartRate: row.averageHeartRate,
            activeKilocalories: row.activeKilocalories,
            health: healthStatusOf(statuses[row.startUtcMs]),
          ),
    ];
  }

  @override
  Future<SavedWorkout?> byId(int id) async {
    final row = await _dao.finishedById(id);
    final end = row?.endUtcMs;
    if (row == null || end == null) return null;
    final (heartRate, points, pauses, statuses) = await (
      _dao.heartRateOf(id),
      _dao.routeOf(id),
      _dao.pausesOf(id),
      _dao.outboxStatusOf([row.startUtcMs]),
    ).wait;
    final workoutPauses = [
      for (final pause in pauses)
        WorkoutPause(
          start: fromUtcMs(pause.startUtcMs),
          end: fromUtcMs(pause.endUtcMs),
        ),
    ];
    final type = WorkoutType.ofActivityType(row.activityType);
    return SavedWorkout(
      id: row.id,
      utcOffset: offsetOf(row.offsetMinutes),
      health: healthStatusOf(statuses[row.startUtcMs]),
      workout: FinishedWorkout(
        type: type,
        start: fromUtcMs(row.startUtcMs),
        end: fromUtcMs(end),
        elapsed: _elapsed(row, end),
        distanceMeters: row.distanceMeters,
        activeKilocalories: row.activeKilocalories,
        averageHeartRate: row.averageHeartRate,
        maxHeartRate: row.maxHeartRate,
        heartRate: [
          for (final sample in heartRate)
            (at: fromUtcMs(sample.atUtcMs), bpm: sample.bpm),
        ],
        pauses: workoutPauses,
        route: WorkoutRoute(
          activityType: type.activityType,
          segments: segmentsAtPauses([
            for (final point in points)
              if (TrackPoint.validLatitude(point.latitude) &&
                  TrackPoint.validLongitude(point.longitude))
                TrackPoint(
                  at: fromUtcMs(point.atUtcMs),
                  latitude: point.latitude,
                  longitude: point.longitude,
                  elevationMeters: point.altitudeMeters,
                  accuracyMeters: point.accuracyMeters,
                ),
          ], workoutPauses),
        ),
      ),
    );
  }

  static Duration _elapsed(WorkoutRow row, int endUtcMs) =>
      Duration(milliseconds: row.elapsedMs ?? endUtcMs - row.startUtcMs);
}

WorkoutHealthStatus healthStatusOf(OutboxStatus? status) => switch (status) {
  null ||
  OutboxStatus.notApplicable ||
  OutboxStatus.disabled => WorkoutHealthStatus.notQueued,
  OutboxStatus.pending => WorkoutHealthStatus.pending,
  OutboxStatus.done => WorkoutHealthStatus.sent,
  OutboxStatus.dead => WorkoutHealthStatus.failed,
};
