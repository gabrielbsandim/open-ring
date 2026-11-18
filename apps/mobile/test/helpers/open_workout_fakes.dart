import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/workouts_dao.dart';

final openStart = DateTime.utc(2026, 11, 10, 7, 10);

DateTime openStartAfter(int hours) => openStart.add(Duration(hours: hours));

// A row as N7 leaves it after a kill: no end, a checkpoint, the elapsed time.
Future<int> insertOpenRow(
  AppDatabase db, {
  DateTime? start,
  Duration elapsed = const Duration(minutes: 21),
  DateTime? checkpoint,
  bool withCheckpoint = true,
  String? deviceId,
  WorkoutType type = WorkoutType.running,
  double? distanceMeters = 3000,
  int offsetMinutes = 0,
}) {
  final begun = start ?? openStart;
  return db
      .into(db.workouts)
      .insert(
        WorkoutsCompanion.insert(
          clientId: WorkoutsDao.clientIdOf(begun),
          activityType: type.activityType,
          deviceId: Value(deviceId),
          startUtcMs: begun.utcMs,
          offsetMinutes: offsetMinutes,
          distanceMeters: Value(distanceMeters),
          elapsedMs: Value(elapsed.inMilliseconds),
          checkpointUtcMs: Value(
            withCheckpoint ? (checkpoint ?? begun.add(elapsed)).utcMs : null,
          ),
        ),
      );
}

Future<int> insertFinishedRow(AppDatabase db, {required DateTime start}) {
  final end = start.add(const Duration(minutes: 30));
  return db
      .into(db.workouts)
      .insert(
        WorkoutsCompanion.insert(
          clientId: WorkoutsDao.clientIdOf(start),
          activityType: WorkoutType.running.activityType,
          startUtcMs: start.utcMs,
          offsetMinutes: 0,
          endUtcMs: Value(end.utcMs),
          elapsedMs: const Value(1800000),
        ),
      );
}

Future<WorkoutRow> rowOf(AppDatabase db, int id) =>
    (db.select(db.workouts)..where((w) => w.id.equals(id))).getSingle();
