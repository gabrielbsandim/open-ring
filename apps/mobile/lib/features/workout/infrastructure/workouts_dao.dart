import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/tables/workout_tables.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';

part 'workouts_dao.g.dart';

@DriftAccessor(
  tables: [Workouts, WorkoutHrSamples, WorkoutRoutePoints, WorkoutPauses],
)
class WorkoutsDao extends DatabaseAccessor<AppDatabase>
    with _$WorkoutsDaoMixin {
  new(super.attachedDatabase);

  static String clientIdOf(DateTime start) => 'phone:${start.utcMs}';

  Future<int> insertFinished(
    FinishedWorkout workout, {
    String? deviceId,
  }) async {
    final id = await into(workouts).insert(
      WorkoutsCompanion.insert(
        clientId: clientIdOf(workout.start),
        activityType: workout.type.activityType,
        deviceId: Value(deviceId),
        startUtcMs: workout.start.utcMs,
        endUtcMs: Value(workout.end.utcMs),
        offsetMinutes: workout.start.offsetMinutes,
        distanceMeters: Value(workout.distanceMeters),
        activeKilocalories: Value(workout.activeKilocalories),
        elapsedMs: Value(workout.elapsed.inMilliseconds),
        averageHeartRate: Value(workout.averageHeartRate),
        maxHeartRate: Value(workout.maxHeartRate),
      ),
    );
    await batch((batch) {
      batch
        ..insertAll(workoutHrSamples, [
          for (final sample in workout.heartRate)
            WorkoutHrSamplesCompanion.insert(
              workoutId: id,
              atUtcMs: sample.at.utcMs,
              offsetMinutes: sample.at.offsetMinutes,
              bpm: sample.bpm,
            ),
        ], mode: InsertMode.insertOrIgnore)
        ..insertAll(workoutRoutePoints, [
          for (final point in workout.route.points)
            WorkoutRoutePointsCompanion.insert(
              workoutId: id,
              atUtcMs: point.at.utcMs,
              offsetMinutes: point.at.offsetMinutes,
              latitude: point.latitude,
              longitude: point.longitude,
              altitudeMeters: Value(point.elevationMeters),
              accuracyMeters: Value(point.accuracyMeters),
            ),
        ], mode: InsertMode.insertOrIgnore)
        ..insertAll(workoutPauses, [
          for (final pause in workout.pauses)
            WorkoutPausesCompanion.insert(
              workoutId: id,
              startUtcMs: pause.start.utcMs,
              endUtcMs: pause.end.utcMs,
            ),
        ], mode: InsertMode.insertOrIgnore);
    });
    return id;
  }

  Future<List<WorkoutRow>> newestFinished({required int limit}) =>
      (select(workouts)
            ..where((w) => w.endUtcMs.isNotNull())
            ..orderBy([
              (w) => OrderingTerm.desc(w.startUtcMs),
              (w) => OrderingTerm.desc(w.id),
            ])
            ..limit(limit))
          .get();

  Future<WorkoutRow?> finishedById(int id) => (select(
    workouts,
  )..where((w) => w.id.equals(id) & w.endUtcMs.isNotNull())).getSingleOrNull();

  Future<List<WorkoutHrSampleRow>> heartRateOf(int id) =>
      (select(workoutHrSamples)
            ..where((s) => s.workoutId.equals(id))
            ..orderBy([(s) => OrderingTerm.asc(s.atUtcMs)]))
          .get();

  Future<List<WorkoutRoutePointRow>> routeOf(int id) =>
      (select(workoutRoutePoints)
            ..where((p) => p.workoutId.equals(id))
            ..orderBy([(p) => OrderingTerm.asc(p.atUtcMs)]))
          .get();

  Future<List<WorkoutPauseRow>> pausesOf(int id) =>
      (select(workoutPauses)
            ..where((p) => p.workoutId.equals(id))
            ..orderBy([(p) => OrderingTerm.asc(p.startUtcMs)]))
          .get();

  // A phone-led workout is enqueued as one outbox row starting at its start,
  // so the newest such row is the one that carries it.
  Future<Map<int, OutboxStatus>> outboxStatusOf(
    Iterable<int> startUtcMs,
  ) async {
    final starts = startUtcMs.toSet();
    if (starts.isEmpty) return const {};
    final outbox = attachedDatabase.healthOutbox;
    final rows =
        await (select(outbox)
              ..where(
                (o) =>
                    o.kind.equalsValue(HealthRecordKind.workout) &
                    o.deviceId.isNull() &
                    o.fromUtcMs.isIn(starts),
              )
              ..orderBy([(o) => OrderingTerm.asc(o.id)]))
            .get();
    return {for (final row in rows) row.fromUtcMs: row.status};
  }

  // The child tables cascade on the workout id (foreign keys are on).
  Future<bool> deleteById(int id) async =>
      await (delete(workouts)..where((w) => w.id.equals(id))).go() > 0;
}
