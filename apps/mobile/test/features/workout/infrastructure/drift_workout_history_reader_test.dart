import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_record_source.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_history_reader.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_store.dart';

import '../../../helpers/database.dart';
import '../../../helpers/workout_fakes.dart';

DateTime at(int seconds) => workoutStart.add(Duration(seconds: seconds));

FinishedWorkout recorded({
  WorkoutType type = WorkoutType.running,
  Duration startAfter = Duration.zero,
  bool? gps,
}) {
  final start = workoutStart.add(startAfter);
  DateTime t(int seconds) => start.add(Duration(seconds: seconds));
  final session = WorkoutSession(
    type: type,
    gps: gps,
    profile: const WorkoutProfile(weightKilograms: 70),
  )..start(start);
  for (var s = 0; s <= 10; s++) {
    session
      ..addFix(fixAt(startAfter + Duration(seconds: s), northMeters: s * 3.0))
      ..addHeartRate(130 + s, t(s));
  }
  session
    ..pause(t(10))
    ..resume(t(70))
    ..addFix(fixAt(startAfter + const Duration(seconds: 71), northMeters: 33))
    ..addFix(fixAt(startAfter + const Duration(seconds: 75), northMeters: 45))
    ..addHeartRate(150, t(71))
    ..finish(t(80));
  return session.finished();
}

void main() {
  late AppDatabase db;
  late DriftWorkoutStore store;
  late DriftWorkoutHistoryReader reader;

  setUp(() {
    db = memoryDatabase();
    store = DriftWorkoutStore(db);
    reader = DriftWorkoutHistoryReader(db);
  });

  test('lists finished workouts newest first, up to the limit', () async {
    final first = await store.save(recorded(), at: at(81));
    final second = await store.save(
      recorded(type: WorkoutType.yoga, startAfter: const Duration(days: 1)),
      at: at(81),
    );
    final third = await store.save(
      recorded(startAfter: const Duration(hours: 2)),
      at: at(81),
    );

    final recent = await reader.recent(limit: 2);

    expect(recent.map((w) => w.id), [second, third]);
    expect(recent.first.type, WorkoutType.yoga);
    expect(recent.first.distanceMeters, isNull);
    expect(recent.last.elapsed, const Duration(seconds: 20));
    expect(recent.last.averageHeartRate, isNotNull);
    expect(recent.last.utcOffset, workoutStart.timeZoneOffset);
    expect((await reader.recent(limit: 5)).map((w) => w.id), [
      second,
      third,
      first,
    ]);
    expect(await reader.recent(limit: 0), isEmpty);
  });

  test('reads one workout with its HR, pauses and split route', () async {
    final id = await store.save(recorded(), at: at(81));

    final saved = await reader.byId(id);

    final workout = saved!.workout;
    expect(saved.id, id);
    expect(workout.type, WorkoutType.running);
    expect(workout.start.isAtSameMomentAs(workoutStart), isTrue);
    expect(workout.end.isAtSameMomentAs(at(80)), isTrue);
    expect(workout.heartRate.map((s) => s.bpm).last, 150);
    expect(workout.heartRate, hasLength(12));
    expect(workout.pauses.single.start.isAtSameMomentAs(at(10)), isTrue);
    expect(workout.pauses.single.end.isAtSameMomentAs(at(70)), isTrue);
    expect(workout.route.segments.map((s) => s.length), [11, 2]);
    expect(workout.route.distanceMeters, closeTo(42, 1e-6));
    expect(workout.gps, isTrue);
  });

  test('an unknown or unfinished id reads as nothing', () async {
    expect(await reader.byId(42), isNull);
    final id = await db
        .into(db.workouts)
        .insert(
          WorkoutsCompanion.insert(
            clientId: 'phone:1',
            activityType: 'running',
            startUtcMs: 1,
            offsetMinutes: 0,
          ),
        );
    expect(await reader.byId(id), isNull);
    expect(await reader.recent(limit: 5), isEmpty);
  });

  test('carries the Health outbox status of each workout', () async {
    final pending = await store.save(recorded(), at: at(81));
    final sent = await store.save(
      recorded(startAfter: const Duration(hours: 1)),
      at: at(81),
    );
    await (db.update(db.healthOutbox)..where(
          (o) => o.fromUtcMs.equals(
            workoutStart.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          ),
        ))
        .write(const HealthOutboxCompanion(status: Value(OutboxStatus.done)));
    final manual = await db
        .into(db.workouts)
        .insert(
          WorkoutsCompanion.insert(
            clientId: 'phone:manual',
            activityType: 'walking',
            startUtcMs: workoutStart
                .add(const Duration(hours: 3))
                .millisecondsSinceEpoch,
            endUtcMs: Value(
              workoutStart.add(const Duration(hours: 4)).millisecondsSinceEpoch,
            ),
            offsetMinutes: 0,
          ),
        );

    final byId = {
      for (final item in await reader.recent(limit: 5)) item.id: item.health,
    };

    expect(byId, {
      pending: WorkoutHealthStatus.pending,
      sent: WorkoutHealthStatus.sent,
      manual: WorkoutHealthStatus.notQueued,
    });
    expect((await reader.byId(sent))!.health, WorkoutHealthStatus.sent);
  });

  test(
    'delete removes the workout and its rows and enqueues nothing',
    () async {
      final id = await store.save(recorded(), at: at(81));
      final keep = await store.save(
        recorded(startAfter: const Duration(hours: 1)),
        at: at(81),
      );
      final outboxBefore = await rowCount(db, 'health_outbox');

      expect(await store.delete(id), isTrue);

      expect(await reader.byId(id), isNull);
      expect((await reader.recent(limit: 5)).map((w) => w.id), [keep]);
      expect(await rowCount(db, 'workout_hr_samples'), 12);
      expect(await rowCount(db, 'workout_route_points'), 13);
      expect(await rowCount(db, 'workout_pauses'), 1);
      expect(await rowCount(db, 'health_outbox'), outboxBefore);
      expect(await store.delete(id), isFalse);
    },
  );

  test('a pending outbox row of a deleted workout writes nothing', () async {
    final id = await store.save(recorded(), at: at(81));
    final row = await HealthOutboxDao(db).due(at(90));
    await store.delete(id);

    final batches = await DriftHealthRecordSource(db)
        .batches(row.single, batchSize: 200);

    expect(row.single.kind, HealthRecordKind.workout);
    expect(batches, isEmpty);
  });
}
