import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_read_store.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/drift_imported_workout_reader.dart';

import '../../../helpers/database.dart';
import '../../../helpers/fake_health_reader.dart';

void main() {
  const watch = 'com.garmin.android.apps.connectmobile';
  const fit = 'com.google.android.apps.fitness';
  final run = DateTime.utc(2026, 11, 9, 18);
  final readAt = DateTime.utc(2026, 11, 10, 9);

  Future<DriftHealthReadStore> seeded(DriftHealthReadStore store) async {
    await store.saveWorkouts([
      externalWorkout(watch, run, id: 'w1'),
      externalWorkout(
        fit,
        run.subtract(const Duration(days: 1)),
        id: 'w2',
        activityType: 'other',
      ),
      externalWorkout(watch, run.subtract(const Duration(days: 2)), id: 'w3'),
    ], readAt: readAt);
    return store;
  }

  test('with reading off it returns nothing and OpenRing alone', () async {
    final db = memoryDatabase();
    await seeded(DriftHealthReadStore(db));
    final reader = DriftImportedWorkoutReader(db);

    final recent = await reader.recent(limit: 5);

    expect(recent.priority, [ringSource]);
    expect(recent.workouts, isEmpty);
    expect(await reader.byRecordId('w1'), isNull);
  });

  test('with reading on it returns the newest first and the order', () async {
    final db = memoryDatabase();
    final store = await seeded(DriftHealthReadStore(db));
    await store.setEnabled(HealthRecordKind.workout, enabled: true);
    await store.savePriority(HealthRecordKind.workout, const [fit, ringSource]);

    final recent = await DriftImportedWorkoutReader(db).recent(limit: 2);

    expect(recent.workouts.map((w) => w.recordId), ['w1', 'w2']);
    expect(recent.priority, [fit, ringSource, watch]);
    expect(recent.workouts.last.type, WorkoutType.other);
  });

  test('opens one workout by its record id', () async {
    final db = memoryDatabase();
    final store = await seeded(DriftHealthReadStore(db));
    await store.setEnabled(HealthRecordKind.workout, enabled: true);
    final reader = DriftImportedWorkoutReader(db);

    final workout = await reader.byRecordId('w1');

    expect(workout!.source, watch);
    expect(workout.type, WorkoutType.running);
    expect(workout.start.toUtc(), run);
    expect(workout.elapsed, const Duration(minutes: 40));
    expect(await reader.byRecordId('missing'), isNull);
  });
}
