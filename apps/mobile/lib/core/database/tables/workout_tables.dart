import 'package:drift/drift.dart';

@DataClassName('WorkoutRow')
class Workouts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientId => text().unique()();
  TextColumn get activityType => text()();
  TextColumn get deviceId => text().nullable()();
  IntColumn get startUtcMs => integer()();
  IntColumn get endUtcMs => integer().nullable()();
  IntColumn get offsetMinutes => integer()();
  RealColumn get distanceMeters => real().nullable()();
  RealColumn get activeKilocalories => real().nullable()();
  IntColumn get elapsedMs => integer().nullable()();
  IntColumn get averageHeartRate => integer().nullable()();
  IntColumn get maxHeartRate => integer().nullable()();
}

@DataClassName('WorkoutHrSampleRow')
class WorkoutHrSamples extends Table {
  IntColumn get workoutId =>
      integer().references(Workouts, #id, onDelete: KeyAction.cascade)();
  IntColumn get atUtcMs => integer()();
  IntColumn get offsetMinutes => integer()();
  IntColumn get bpm => integer()();

  @override
  Set<Column<Object>> get primaryKey => {workoutId, atUtcMs};
}

@DataClassName('WorkoutRoutePointRow')
class WorkoutRoutePoints extends Table {
  IntColumn get workoutId =>
      integer().references(Workouts, #id, onDelete: KeyAction.cascade)();
  IntColumn get atUtcMs => integer()();
  IntColumn get offsetMinutes => integer()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get altitudeMeters => real().nullable()();
  RealColumn get accuracyMeters => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {workoutId, atUtcMs};
}

@DataClassName('WorkoutPauseRow')
class WorkoutPauses extends Table {
  IntColumn get workoutId =>
      integer().references(Workouts, #id, onDelete: KeyAction.cascade)();
  IntColumn get startUtcMs => integer()();
  IntColumn get endUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {workoutId, startUtcMs};
}
