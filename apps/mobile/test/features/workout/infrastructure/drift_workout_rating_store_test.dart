import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_read_store.dart';
import 'package:open_ring/features/workout/domain/workout_rating_store.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/drift_imported_workout_reader.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_history_reader.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_rating_store.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_store.dart';

import '../../../helpers/database.dart';
import '../../../helpers/fake_health_reader.dart';
import '../../../helpers/workout_fakes.dart';

FinishedWorkout recorded() {
  final session = WorkoutSession(
    type: WorkoutType.running,
    profile: const WorkoutProfile(weightKilograms: 70),
  )..start(workoutStart);
  for (var s = 0; s <= 10; s++) {
    session.addHeartRate(130 + s, workoutStart.add(Duration(seconds: s)));
  }
  session.finish(workoutStart.add(const Duration(seconds: 80)));
  return session.finished();
}

void main() {
  const watch = 'com.garmin.android.apps.connectmobile';
  final run = DateTime.utc(2026, 11, 9, 18);
  final readAt = DateTime.utc(2026, 11, 10, 9);
  late AppDatabase db;
  late WorkoutRatingStore ratings;
  late DriftWorkoutHistoryReader recordedReader;
  late DriftImportedWorkoutReader importedReader;
  late DriftHealthReadStore health;
  late int id;

  Future<int?> recordedRating() async =>
      (await recordedReader.byId(id))?.rating;

  Future<int?> importedRating([String recordId = 'w1']) async =>
      (await importedReader.byRecordId(recordId))?.rating;

  setUp(() async {
    db = memoryDatabase();
    ratings = DriftWorkoutRatingStore(db);
    recordedReader = DriftWorkoutHistoryReader(db);
    importedReader = DriftImportedWorkoutReader(db);
    health = DriftHealthReadStore(db);
    id = await DriftWorkoutStore(db).save(recorded(), at: workoutStart);
    await health.saveWorkouts([
      externalWorkout(watch, run, id: 'w1'),
    ], readAt: readAt);
    await health.setEnabled(HealthRecordKind.workout, enabled: true);
  });

  group('criterion 2: rating a recorded workout', () {
    test('a fresh workout has no rating on any read path', () async {
      expect((await recordedReader.recent(limit: 5)).single.rating, isNull);
      expect(await recordedRating(), isNull);
    });

    test('7 reads back on recent, intersecting and byId', () async {
      expect(await ratings.rateRecorded(id, 7), isTrue);

      final recent = await recordedReader.recent(limit: 5);
      final around = await recordedReader.intersecting(
        from: workoutStart.subtract(const Duration(hours: 1)),
        to: workoutStart.add(const Duration(hours: 1)),
      );
      expect(recent.single.rating, 7);
      expect(around.single.rating, 7);
      expect(await recordedRating(), 7);
    });

    test('the bounds 1 and 10 are accepted', () async {
      expect(await ratings.rateRecorded(id, effortMinRating), isTrue);
      expect(await recordedRating(), 1);
      expect(await ratings.rateRecorded(id, effortMaxRating), isTrue);
      expect(await recordedRating(), 10);
    });

    test('null clears the rating', () async {
      await ratings.rateRecorded(id, 7);

      expect(await ratings.rateRecorded(id, null), isTrue);

      expect(await recordedRating(), isNull);
      expect((await recordedReader.recent(limit: 5)).single.rating, isNull);
    });

    test('0, 11 and -1 throw and leave the stored rating alone', () async {
      await ratings.rateRecorded(id, 7);

      for (final bad in [0, 11, -1]) {
        await expectLater(
          ratings.rateRecorded(id, bad),
          throwsArgumentError,
          reason: '$bad',
        );
      }
      expect(await recordedRating(), 7);
    });

    test('an unknown id returns false and writes nothing', () async {
      expect(await ratings.rateRecorded(id + 100, 7), isFalse);
      expect(await recordedRating(), isNull);
    });
  });

  group('criterion 2: rating an imported workout', () {
    test('a fresh import has no rating', () async {
      expect(await importedRating(), isNull);
      final recent = await importedReader.recent(limit: 5);
      expect(recent.workouts.single.rating, isNull);
    });

    test('7 reads back on recent, intersecting and byRecordId', () async {
      expect(await ratings.rateImported('w1', 7), isTrue);

      final recent = await importedReader.recent(limit: 5);
      final around = await importedReader.intersecting(
        from: run.subtract(const Duration(hours: 1)),
        to: run.add(const Duration(hours: 1)),
      );
      expect(recent.workouts.single.rating, 7);
      expect(around.workouts.single.rating, 7);
      expect(await importedRating(), 7);
    });

    test('the bounds 1 and 10 are accepted', () async {
      expect(await ratings.rateImported('w1', effortMinRating), isTrue);
      expect(await importedRating(), 1);
      expect(await ratings.rateImported('w1', effortMaxRating), isTrue);
      expect(await importedRating(), 10);
    });

    test('null clears the rating', () async {
      await ratings.rateImported('w1', 7);

      expect(await ratings.rateImported('w1', null), isTrue);

      expect(await importedRating(), isNull);
    });

    test('0, 11 and -1 throw and leave the stored rating alone', () async {
      await ratings.rateImported('w1', 7);

      for (final bad in [0, 11, -1]) {
        await expectLater(
          ratings.rateImported('w1', bad),
          throwsArgumentError,
          reason: '$bad',
        );
      }
      expect(await importedRating(), 7);
    });

    test('an unknown record id returns false and writes nothing', () async {
      expect(await ratings.rateImported('nope', 7), isFalse);
      expect(await importedRating(), isNull);
    });

    test('rating one import leaves another import unrated', () async {
      await health.saveWorkouts([
        externalWorkout(watch, run, id: 'w1'),
        externalWorkout(watch, run.subtract(const Duration(days: 1)), id: 'w2'),
      ], readAt: readAt);

      await ratings.rateImported('w1', 7);

      expect(await importedRating(), 7);
      expect(await importedRating('w2'), isNull);
    });
  });

  group('criterion 3: a re-import and the rating', () {
    test('the same record with another type keeps the rating', () async {
      await ratings.rateImported('w1', 7);

      await health.saveWorkouts([
        externalWorkout(watch, run, id: 'w1', activityType: 'yoga'),
      ], readAt: readAt.add(const Duration(hours: 1)));

      final workout = (await importedReader.byRecordId('w1'))!;
      expect(workout.type, WorkoutType.yoga);
      expect(workout.rating, 7);
    });

    test('a cleared rating stays cleared after a sync', () async {
      await ratings.rateImported('w1', 7);
      await ratings.rateImported('w1', null);

      await health.saveWorkouts([
        externalWorkout(watch, run, id: 'w1', activityType: 'yoga'),
      ], readAt: readAt.add(const Duration(hours: 1)));

      expect(await importedRating(), isNull);
    });

    test('a record absent from the coverage is gone with its rating', () async {
      await ratings.rateImported('w1', 7);

      await health.saveWorkouts(
        const [],
        readAt: readAt.add(const Duration(hours: 1)),
        coverage: (
          from: run.subtract(const Duration(days: 1)),
          to: run.add(const Duration(days: 1)),
          present: <String>{},
        ),
      );

      expect(await importedReader.byRecordId('w1'), isNull);
      expect(await rowCount(db, 'imported_workouts'), 0);
    });

    test('a record present in the coverage keeps its rating', () async {
      await ratings.rateImported('w1', 7);

      await health.saveWorkouts(
        [externalWorkout(watch, run, id: 'w1')],
        readAt: readAt.add(const Duration(hours: 1)),
        coverage: (
          from: run.subtract(const Duration(days: 1)),
          to: run.add(const Duration(days: 1)),
          present: {'w1'},
        ),
      );

      expect(await importedRating(), 7);
    });
  });

  group('criterion 4: a stored value outside the scale reads as null', () {
    test('a raw 0, 11 or -3 on a recorded workout', () async {
      for (final raw in [0, 11, -3]) {
        await db.customStatement(
          'UPDATE workouts SET effort_rating = $raw WHERE id = $id',
        );

        expect(await recordedRating(), isNull, reason: '$raw');
        expect(
          (await recordedReader.recent(limit: 5)).single.rating,
          isNull,
          reason: '$raw',
        );
        final around = await recordedReader.intersecting(
          from: workoutStart.subtract(const Duration(hours: 1)),
          to: workoutStart.add(const Duration(hours: 1)),
        );
        expect(around.single.rating, isNull, reason: '$raw');
      }
    });

    test('a raw 0, 11 or -3 on an imported workout', () async {
      for (final raw in [0, 11, -3]) {
        await db.customStatement(
          'UPDATE imported_workouts SET effort_rating = $raw '
          "WHERE record_id = 'w1'",
        );

        expect(await importedRating(), isNull, reason: '$raw');
        final recent = await importedReader.recent(limit: 5);
        expect(recent.workouts.single.rating, isNull, reason: '$raw');
        final around = await importedReader.intersecting(
          from: run.subtract(const Duration(hours: 1)),
          to: run.add(const Duration(hours: 1)),
        );
        expect(around.workouts.single.rating, isNull, reason: '$raw');
      }
    });

    test('a raw 1 and 10 still read as stored', () async {
      await db.customStatement(
        'UPDATE workouts SET effort_rating = 1 WHERE id = $id',
      );
      await db.customStatement(
        'UPDATE imported_workouts SET effort_rating = 10 '
        "WHERE record_id = 'w1'",
      );

      expect(await recordedRating(), 1);
      expect(await importedRating(), 10);
    });
  });
}
