import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_store.dart';

import '../../../helpers/database.dart';
import '../../../helpers/workout_fakes.dart';

DateTime at(int seconds) => workoutStart.add(Duration(seconds: seconds));

WorkoutSession runFor(int seconds) {
  final session = WorkoutSession(
    type: WorkoutType.running,
    profile: const WorkoutProfile(weightKilograms: 70),
  )..start(workoutStart);
  addSeconds(session, from: 0, to: seconds);
  return session;
}

void addSeconds(WorkoutSession session, {required int from, required int to}) {
  for (var s = from; s <= to; s++) {
    session
      ..addFix(fixAt(Duration(seconds: s), northMeters: s * 3.0))
      ..addHeartRate(130 + s % 20, at(s));
  }
}

void main() {
  late AppDatabase db;
  late DriftWorkoutStore store;

  setUp(() {
    db = memoryDatabase();
    store = DriftWorkoutStore(db);
  });

  Future<WorkoutRow> single() => db.select(db.workouts).getSingle();

  test(
    'a checkpoint writes one open row and queues nothing for Health',
    () async {
      final session = runFor(60);

      await store.checkpoint(session, at: at(60));

      final row = await single();
      expect(row.clientId, 'phone:${workoutStart.utcMs}');
      expect(row.deviceId, isNull);
      expect(row.startUtcMs, workoutStart.utcMs);
      expect(row.endUtcMs, isNull);
      expect(row.checkpointUtcMs, at(60).utcMs);
      expect(row.elapsedMs, 60000);
      expect(row.distanceMeters, closeTo(180, 1e-6));
      expect(await rowCount(db, 'workout_hr_samples'), 61);
      expect(await rowCount(db, 'workout_route_points'), 61);
      expect(await rowCount(db, 'health_outbox'), 0);
    },
  );

  test(
    'a paused checkpoint ends at the pause and writes no open pause',
    () async {
      final session = runFor(30)
        ..pause(at(10))
        ..resume(at(20))
        ..pause(at(30));

      await store.checkpoint(session, at: at(95));

      final row = await single();
      expect(row.endUtcMs, isNull);
      expect(row.checkpointUtcMs, at(30).utcMs);
      expect(row.elapsedMs, 20000);
      final pauses = await db.select(db.workoutPauses).get();
      expect(pauses.map((p) => (p.startUtcMs, p.endUtcMs)), [
        (at(10).utcMs, at(20).utcMs),
      ]);
    },
  );

  test('a checkpoint after the clock stepped back does not end before the '
      'last sample', () async {
    final session = runFor(40);

    await store.checkpoint(session, at: at(20));

    final row = await single();
    expect(row.checkpointUtcMs, greaterThanOrEqualTo(at(40).utcMs));
  });

  test(
    'save after a checkpoint closes the same row with one outbox row',
    () async {
      final session = runFor(60);
      await store.checkpoint(session, at: at(60));
      final open = await single();
      addSeconds(session, from: 61, to: 90);
      session.finish(at(90));

      final id = await store.save(session.finished(), at: at(91));

      final row = await single();
      expect(id, open.id);
      expect(row.id, open.id);
      expect(row.endUtcMs, at(90).utcMs);
      expect(row.checkpointUtcMs, isNull);
      expect(row.elapsedMs, 90000);
      expect(await rowCount(db, 'workout_hr_samples'), 91);
      expect(await rowCount(db, 'workout_route_points'), 91);
      final outbox = await HealthOutboxDao(db).all();
      expect(outbox.map((r) => (r.kind, r.fromUtcMs, r.toUtcMs)), [
        (HealthRecordKind.workout, workoutStart.utcMs, at(90).utcMs),
      ]);
    },
  );

  test('a checkpoint called after save leaves the row closed', () async {
    final session = runFor(60);
    await store.checkpoint(session, at: at(60));
    session.finish(at(70));
    await store.save(session.finished(), at: at(71));
    final closed = await single();

    // The spec leaves open whether this throws or does nothing; only the
    // stored row is the contract.
    await Future.sync(() => store.checkpoint(session, at: at(120)))
        .then<void>((_) {}, onError: (Object _) {});

    expect(await single(), closed);
    expect(await rowCount(db, 'workout_hr_samples'), 61);
    expect(await rowCount(db, 'health_outbox'), 1);
  });

  test('dropping a checkpoint leaves no workout rows', () async {
    final session = runFor(60);
    await store.checkpoint(session, at: at(60));
    session.discard(at(65));

    await store.dropCheckpoint(session);

    expect(await rowCount(db, 'workouts'), 0);
    expect(await rowCount(db, 'workout_hr_samples'), 0);
    expect(await rowCount(db, 'workout_route_points'), 0);
    expect(await rowCount(db, 'health_outbox'), 0);
  });

  test('dropping a checkpoint never deletes a saved workout', () async {
    final session = runFor(10)..finish(at(10));
    await store.save(session.finished(), at: at(11));

    await store.dropCheckpoint(session);

    expect(await rowCount(db, 'workouts'), 1);
    expect((await single()).endUtcMs, at(10).utcMs);
  });
}
