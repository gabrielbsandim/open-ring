import 'package:drift/drift.dart';
import 'package:open_ring/core/database/tables/ring_tables.dart';

mixin RingSample on Table {
  TextColumn get deviceId => text().references(RingDevices, #deviceId)();
  IntColumn get atUtcMs => integer()();
  IntColumn get offsetMinutes => integer()();
}

@DataClassName('ActivityBucketRow')
class ActivityBuckets extends Table {
  TextColumn get deviceId => text().references(RingDevices, #deviceId)();
  IntColumn get startUtcMs => integer()();
  IntColumn get offsetMinutes => integer()();
  IntColumn get durationSeconds => integer()();
  IntColumn get steps => integer()();
  IntColumn get distanceMeters => integer()();
  RealColumn get activeKilocalories => real()();

  @override
  Set<Column<Object>> get primaryKey => {deviceId, startUtcMs};
}

@DataClassName('HrSampleRow')
class HrSamples extends Table with RingSample {
  IntColumn get bpm => integer()();

  @override
  Set<Column<Object>> get primaryKey => {deviceId, atUtcMs};
}

@DataClassName('Spo2SampleRow')
class Spo2Samples extends Table with RingSample {
  IntColumn get percent => integer()();

  @override
  Set<Column<Object>> get primaryKey => {deviceId, atUtcMs};
}

@DataClassName('StressSampleRow')
class StressSamples extends Table with RingSample {
  IntColumn get level => integer()();

  @override
  Set<Column<Object>> get primaryKey => {deviceId, atUtcMs};
}

@DataClassName('HrvSampleRow')
class HrvSamples extends Table with RingSample {
  IntColumn get milliseconds => integer()();

  @override
  Set<Column<Object>> get primaryKey => {deviceId, atUtcMs};
}
