import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/demo/domain/demo_data.dart';
import 'package:open_ring/features/demo/domain/demo_data_generator.dart';
import 'package:open_ring/features/demo/infrastructure/demo_workout_store.dart';
import 'package:open_ring/features/demo/infrastructure/drift_demo_data_store.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/database.dart';

final now = DateTime.utc(2026, 11, 11, 14, 37);
final liveStart = DateTime.utc(2026, 11, 11, 14, 30, 17);

DateTime at(int seconds) => liveStart.add(Duration(seconds: seconds));

WorkoutSession runFor(int seconds) {
  final session = WorkoutSession(
    type: WorkoutType.other,
    profile: const WorkoutProfile(weightKilograms: 70),
  )..start(liveStart);
  addSeconds(session, from: 0, to: seconds);
  return session;
}

void addSeconds(WorkoutSession session, {required int from, required int to}) {
  for (var s = from; s <= to; s++) {
    session.addHeartRate(120 + s % 15, at(s));
  }
}

void main() {
  late AppDatabase db;
  late DemoWorkoutStore store;

  setUp(() {
    db = memoryDatabase();
    store = DemoWorkoutStore(db);
  });

  Future<List<WorkoutRow>> liveRows() => (db.select(
    db.workouts,
  )..where((w) => w.startUtcMs.equals(liveStart.utcMs))).get();

  test('a demo checkpoint carries the demo ring and queues nothing', () async {
    final session = runFor(60);

    await store.checkpoint(session, at: at(60));

    final row = (await liveRows()).single;
    expect(row.deviceId, demoDeviceId);
    expect(row.endUtcMs, isNull);
    expect(row.checkpointUtcMs, at(60).utcMs);
    expect(await rowCount(db, 'health_outbox'), 0);
  });

  test(
    'a demo save after a checkpoint closes the same row and queues nothing',
    () async {
      final session = runFor(60);
      await store.checkpoint(session, at: at(60));
      final open = (await liveRows()).single;
      addSeconds(session, from: 61, to: 80);
      session.finish(at(80));

      final id = await store.save(session.finished(), at: at(81));

      final row = (await liveRows()).single;
      expect(id, open.id);
      expect(row.id, open.id);
      expect(row.deviceId, demoDeviceId);
      expect(row.endUtcMs, at(80).utcMs);
      expect(row.checkpointUtcMs, isNull);
      expect(await rowCount(db, 'workout_hr_samples'), 81);
      expect(await rowCount(db, 'health_outbox'), 0);
    },
  );

  test('discarding a demo workout after a checkpoint leaves no row', () async {
    final session = runFor(60);
    await store.checkpoint(session, at: at(60));
    session.discard(at(70));

    await store.dropCheckpoint(session);

    expect(await rowCount(db, 'workouts'), 0);
    expect(await rowCount(db, 'workout_hr_samples'), 0);
  });

  test('a demo refresh during a live demo workout still ends with one saved '
      'row for it', () async {
    final demo = DriftDemoDataStore(db);
    final data = DemoDataGenerator(now: now).generate();
    final session = runFor(60);
    await store.checkpoint(session, at: at(60));

    await demo.replace(data);
    addSeconds(session, from: 61, to: 120);
    await store.checkpoint(session, at: at(120));
    session.finish(at(130));
    await store.save(session.finished(), at: at(131));

    final row = (await liveRows()).single;
    expect(row.deviceId, demoDeviceId);
    expect(row.endUtcMs, at(130).utcMs);
    expect(row.checkpointUtcMs, isNull);
    final samples = await (db.select(
      db.workoutHrSamples,
    )..where((s) => s.workoutId.equals(row.id))).get();
    expect(samples, hasLength(121));
    expect(await rowCount(db, 'workouts'), data.workouts.length + 1);
    expect(await rowCount(db, 'health_outbox'), 0);
  });
}
