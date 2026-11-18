import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/workouts_dao.dart';

import '../../../helpers/database.dart';
import '../../../helpers/workout_fakes.dart';

DateTime at(int seconds) => workoutStart.add(Duration(seconds: seconds));

WorkoutSession started() => WorkoutSession(
  type: WorkoutType.running,
  profile: const WorkoutProfile(weightKilograms: 70),
)..start(workoutStart);

void runUntil(WorkoutSession session, {required int from, required int to}) {
  for (var s = from; s <= to; s++) {
    session
      ..addFix(fixAt(Duration(seconds: s), northMeters: s * 3.0))
      ..addHeartRate(130 + s % 20, at(s));
  }
}

void main() {
  late AppDatabase db;
  late WorkoutsDao dao;

  setUp(() {
    db = memoryDatabase();
    dao = WorkoutsDao(db);
  });

  Future<WorkoutRow> single() => db.select(db.workouts).getSingle();

  test('a second checkpoint updates the open row in place and appends the new '
      'children once', () async {
    final session = started();
    runUntil(session, from: 0, to: 60);
    await dao.writeCheckpoint(session.progressAt(at(60)), at: at(60));
    final first = await single();
    runUntil(session, from: 61, to: 120);

    await dao.writeCheckpoint(session.progressAt(at(120)), at: at(120));

    final row = await single();
    expect(row.id, first.id);
    expect(row.clientId, WorkoutsDao.clientIdOf(workoutStart));
    expect(row.endUtcMs, isNull);
    expect(row.checkpointUtcMs, at(120).utcMs);
    expect(row.elapsedMs, 120000);
    expect(await rowCount(db, 'workout_hr_samples'), 121);
    expect(await rowCount(db, 'workout_route_points'), 121);
  });

  test('closeOrInsert closes the open row with the same id', () async {
    final session = started();
    runUntil(session, from: 0, to: 60);
    await dao.writeCheckpoint(session.progressAt(at(60)), at: at(60));
    final open = await single();
    session
      ..pause(at(70))
      ..resume(at(80));
    runUntil(session, from: 80, to: 90);
    session.finish(at(90));

    await dao.closeOrInsert(session.finished(), effortRating: 6);

    final row = await single();
    expect(row.id, open.id);
    expect(row.endUtcMs, at(90).utcMs);
    expect(row.checkpointUtcMs, isNull);
    expect(row.elapsedMs, 80000);
    expect(row.effortRating, 6);
    expect(await rowCount(db, 'workout_hr_samples'), 72);
    final pauses = await db.select(db.workoutPauses).get();
    expect(pauses.map((p) => (p.startUtcMs, p.endUtcMs)), [
      (at(70).utcMs, at(80).utcMs),
    ]);
  });

  test(
    'closeOrInsert inserts a finished row when no checkpoint was written',
    () async {
      final session = started();
      runUntil(session, from: 0, to: 10);
      session.finish(at(10));

      await dao.closeOrInsert(session.finished(), deviceId: 'DEMO');

      final row = await single();
      expect(row.endUtcMs, at(10).utcMs);
      expect(row.checkpointUtcMs, isNull);
      expect(row.deviceId, 'DEMO');
      expect(await rowCount(db, 'workout_hr_samples'), 11);
    },
  );

  test('a late checkpoint never touches a row whose end is set', () async {
    final session = started();
    runUntil(session, from: 0, to: 60);
    final stale = session.progressAt(at(60));
    runUntil(session, from: 61, to: 90);
    session.finish(at(90));
    await dao.closeOrInsert(session.finished());
    final closed = await single();

    await dao.writeCheckpoint(stale, at: at(60));

    final row = await single();
    expect(row, closed);
    expect(row.endUtcMs, at(90).utcMs);
    expect(row.checkpointUtcMs, isNull);
    expect(await rowCount(db, 'workouts'), 1);
    expect(await rowCount(db, 'workout_hr_samples'), 91);
  });

  test('a save takes over the row recovery closed under the same start, with '
      'its own end and elapsed time', () async {
    final session = started();
    runUntil(session, from: 0, to: 60);
    await dao.writeCheckpoint(session.progressAt(at(60)), at: at(60));
    final open = await single();
    await dao.closeOpen(workoutStart);
    runUntil(session, from: 61, to: 90);
    session.finish(at(90));

    final id = await dao.closeOrInsert(session.finished());

    final row = await single();
    expect(id, open.id);
    expect(row.id, open.id);
    expect(row.endUtcMs, at(90).utcMs);
    expect(row.elapsedMs, 90000);
    expect(row.checkpointUtcMs, isNull);
    expect(await rowCount(db, 'workouts'), 1);
    expect(await rowCount(db, 'workout_hr_samples'), 91);
  });

  test(
    'a saved row still fails closeOrInsert on the unique client id',
    () async {
      final session = started();
      runUntil(session, from: 0, to: 10);
      session.finish(at(10));
      await dao.closeOrInsert(session.finished());
      final saved = await single();

      await expectLater(
        dao.closeOrInsert(session.finished()),
        throwsA(isA<SqliteException>()),
      );

      expect(await single(), saved);
    },
  );
}
