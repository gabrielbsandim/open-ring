import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_record_source.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_store.dart';

import '../../../helpers/database.dart';
import '../../../helpers/workout_fakes.dart';

DateTime at(int seconds) => workoutStart.add(Duration(seconds: seconds));

FinishedWorkout recorded() {
  final session = WorkoutSession(
    type: WorkoutType.running,
    profile: const WorkoutProfile(weightKilograms: 70),
  )..start(workoutStart);
  for (var s = 0; s <= 10; s++) {
    session
      ..addFix(fixAt(Duration(seconds: s), northMeters: s * 3.0))
      ..addHeartRate(130 + s, at(s));
  }
  session
    ..pause(at(10))
    ..resume(at(70))
    ..addFix(fixAt(const Duration(seconds: 71), northMeters: 100))
    ..addHeartRate(150, at(71))
    ..finish(at(80));
  return session.finished();
}

void main() {
  test('saves the session, HR, route and pauses in one go', () async {
    final db = memoryDatabase();

    final id = await DriftWorkoutStore(db).save(recorded(), at: at(81));

    final workout = await db.select(db.workouts).getSingle();
    expect(workout.id, id);
    expect(workout.clientId, 'phone:${workoutStart.utcMs}');
    expect(workout.activityType, 'running');
    expect(workout.deviceId, isNull);
    expect(
      (workout.startUtcMs, workout.endUtcMs),
      (workoutStart.utcMs, at(80).utcMs),
    );
    expect(workout.elapsedMs, 20000);
    expect(workout.distanceMeters, closeTo(30, 1e-6));
    expect(workout.activeKilocalories, closeTo(8.8 * 70 * 20 / 3600, 1e-9));
    expect(workout.averageHeartRate, 136);
    expect(workout.maxHeartRate, 150);

    final heartRate = await db.select(db.workoutHrSamples).get();
    expect(heartRate.map((s) => s.bpm), [
      for (var s = 0; s <= 10; s++) 130 + s,
      150,
    ]);
    final route = await db.select(db.workoutRoutePoints).get();
    expect(route, hasLength(12));
    expect(route.first.accuracyMeters, 5);
    final pauses = await db.select(db.workoutPauses).get();
    expect(pauses.map((p) => (p.startUtcMs, p.endUtcMs)), [
      (at(10).utcMs, at(70).utcMs),
    ]);
  });

  test(
    'enqueues one workout row that hands HR and route to the writer',
    () async {
      final db = memoryDatabase();
      await DriftWorkoutStore(db).save(recorded(), at: at(81));

      final rows = await HealthOutboxDao(db).all();
      expect(rows, hasLength(1));
      expect(rows.single.kind, HealthRecordKind.workout);
      expect(rows.single.deviceId, isNull);
      expect(
        (rows.single.fromUtcMs, rows.single.toUtcMs),
        (workoutStart.utcMs, at(80).utcMs),
      );
      expect(rows.single.enqueuedAtUtcMs, at(81).utcMs);

      final entry = (await HealthOutboxDao(db).due(at(82))).single;
      final batches = await DriftHealthRecordSource(db)
          .batches(entry, batchSize: 200);
      final written = batches.single.entries.single as WorkoutEntry;
      expect(written.activityType, 'running');
      expect(written.heartRate, hasLength(12));
      expect(written.route, hasLength(12));
      expect(written.distanceMeters, closeTo(30, 1e-6));
    },
  );

  test('a failed write leaves neither a workout nor an outbox row', () async {
    final db = memoryDatabase();
    final workout = recorded();
    await DriftWorkoutStore(db).save(workout, at: at(81));

    await expectLater(
      DriftWorkoutStore(db).save(workout, at: at(90)),
      throwsA(anything),
    );

    expect(await rowCount(db, 'workouts'), 1);
    expect(await rowCount(db, 'health_outbox'), 1);
  });

  test('deleting a workout drops its pauses', () async {
    final db = memoryDatabase();
    await DriftWorkoutStore(db).save(recorded(), at: at(81));

    await db.delete(db.workouts).go();

    expect(await rowCount(db, 'workout_pauses'), 0);
  });
}
