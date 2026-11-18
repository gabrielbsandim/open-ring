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
    int? effortRating,
  }) => _write(
    null,
    _finished(workout, deviceId: deviceId, effortRating: effortRating),
    workout,
  );

  // A row whose end is set is saved, so a checkpoint that lost the race with
  // save leaves it alone.
  Future<void> writeCheckpoint(
    FinishedWorkout workout, {
    required DateTime at,
    String? deviceId,
  }) => transaction(() async {
    final row = await _byStart(workout.start);
    if (row?.endUtcMs != null) return;
    final columns = _columns(
      workout,
      deviceId: deviceId,
    ).copyWith(checkpointUtcMs: Value(at.utcMs));
    await _write(row?.id, columns, workout);
  });

  // A saved row with the same start fails on the unique client id, as it did
  // before checkpoints.
  Future<int> closeOrInsert(
    FinishedWorkout workout, {
    String? deviceId,
    int? effortRating,
  }) => transaction(() async {
    final row = await _byStart(workout.start);
    return await _write(
      _takesOver(row) ? row?.id : null,
      _finished(workout, deviceId: deviceId, effortRating: effortRating),
      workout,
    );
  });

  Future<void> deleteOpen(DateTime? start) async {
    if (start == null) return;
    await (delete(workouts)..where(
          (w) => w.clientId.equals(clientIdOf(start)) & w.endUtcMs.isNull(),
        ))
        .go();
  }

  Future<List<DateTime>> openStarts() =>
      (selectOnly(workouts)
            ..addColumns([workouts.startUtcMs])
            ..where(workouts.endUtcMs.isNull())
            ..orderBy([OrderingTerm.asc(workouts.startUtcMs)]))
          .map((row) => utcInstant(row.read(workouts.startUtcMs)!))
          .get();

  // Only a row with no end changes, so one another engine saved in the
  // meantime keeps its end, its elapsed time and its outbox row.
  Future<WorkoutRow?> closeOpen(DateTime start) async {
    final closed =
        await (update(workouts)..where(
              (w) => w.clientId.equals(clientIdOf(start)) & w.endUtcMs.isNull(),
            ))
            .writeReturning(
              WorkoutsCompanion.custom(
                endUtcMs: coalesce([
                  workouts.checkpointUtcMs,
                  workouts.startUtcMs +
                      coalesce([workouts.elapsedMs, const Constant(0)]),
                ]),
              ),
            );
    return closed.singleOrNull;
  }

  // Recovery keeps the checkpoint on the row it closes, so a live engine it
  // took for dead can still save over that row; a saved row has none.
  static bool _takesOver(WorkoutRow? row) =>
      row != null && (row.endUtcMs == null || row.checkpointUtcMs != null);

  Future<WorkoutRow?> _byStart(DateTime start) => (select(
    workouts,
  )..where((w) => w.clientId.equals(clientIdOf(start)))).getSingleOrNull();

  WorkoutsCompanion _columns(FinishedWorkout workout, {String? deviceId}) =>
      WorkoutsCompanion.insert(
        clientId: clientIdOf(workout.start),
        activityType: workout.type.activityType,
        deviceId: Value(deviceId),
        startUtcMs: workout.start.utcMs,
        offsetMinutes: workout.start.offsetMinutes,
        distanceMeters: Value(workout.distanceMeters),
        activeKilocalories: Value(workout.activeKilocalories),
        elapsedMs: Value(workout.elapsed.inMilliseconds),
        averageHeartRate: Value(workout.averageHeartRate),
        maxHeartRate: Value(workout.maxHeartRate),
      );

  WorkoutsCompanion _finished(
    FinishedWorkout workout, {
    String? deviceId,
    int? effortRating,
  }) => _columns(workout, deviceId: deviceId).copyWith(
    endUtcMs: Value(workout.end.utcMs),
    effortRating: Value(effortRating),
    checkpointUtcMs: const Value(null),
  );

  // Children are keyed by their instant, so writing the whole session again
  // appends only what is new.
  Future<int> _write(
    int? existing,
    WorkoutsCompanion columns,
    FinishedWorkout workout,
  ) async {
    final id = switch (existing) {
      null => await into(workouts).insert(columns),
      final id => await _update(id, columns),
    };
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

  Future<int> _update(int id, WorkoutsCompanion columns) async {
    await (update(workouts)..where((w) => w.id.equals(id))).write(columns);
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

  Future<List<WorkoutRow>> finishedIntersecting({
    required int fromUtcMs,
    required int toUtcMs,
  }) =>
      (select(workouts)
            ..where(
              (w) =>
                  w.endUtcMs.isNotNull() &
                  w.endUtcMs.isBiggerThanValue(fromUtcMs) &
                  w.startUtcMs.isSmallerThanValue(toUtcMs),
            )
            ..orderBy([
              (w) => OrderingTerm.asc(w.startUtcMs),
              (w) => OrderingTerm.asc(w.id),
            ]))
          .get();

  Future<List<int>> routedIds({
    required int fromUtcMs,
    required int toUtcMs,
    required Iterable<String> activityTypes,
  }) =>
      (selectOnly(workouts)
            ..addColumns([workouts.id])
            ..where(
              workouts.endUtcMs.isNotNull() &
                  workouts.distanceMeters.isNotNull() &
                  workouts.startUtcMs.isBiggerOrEqualValue(fromUtcMs) &
                  workouts.startUtcMs.isSmallerThanValue(toUtcMs) &
                  workouts.activityType.isIn(activityTypes),
            )
            ..orderBy([OrderingTerm.asc(workouts.startUtcMs)]))
          .map((row) => row.read(workouts.id)!)
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
