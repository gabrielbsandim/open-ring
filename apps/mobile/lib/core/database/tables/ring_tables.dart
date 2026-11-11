import 'package:drift/drift.dart';
import 'package:open_ring/core/records/record_kind.dart';

@DataClassName('RingDeviceRow')
class RingDevices extends Table {
  TextColumn get deviceId => text()();
  TextColumn get name => text()();
  TextColumn get model => text().nullable()();
  TextColumn get firmware => text().nullable()();
  IntColumn get pairedAtUtcMs => integer()();
  IntColumn get lastSyncAtUtcMs => integer().nullable()();
  IntColumn get batteryPercent => integer().nullable()();
  BoolColumn get batteryCharging => boolean().nullable()();
  IntColumn get batteryAtUtcMs => integer().nullable()();
  IntColumn get unpairedAtUtcMs => integer().nullable()();
  BoolColumn get autoHeartRate => boolean().withDefault(const Constant(true))();
  BoolColumn get autoSpo2 => boolean().withDefault(const Constant(true))();
  BoolColumn get autoStress => boolean().withDefault(const Constant(true))();
  BoolColumn get autoHrv => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {deviceId};
}

@DataClassName('SyncRunRow')
class SyncRuns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get deviceId => text().references(RingDevices, #deviceId)();
  IntColumn get atUtcMs => integer()();
  TextColumn get outcome => text()();
  TextColumn get kinds => text().withDefault(const Constant(''))();
  IntColumn get recordCount => integer().withDefault(const Constant(0))();
}

@DataClassName('SyncCursorRow')
class SyncCursors extends Table {
  TextColumn get deviceId => text().references(RingDevices, #deviceId)();
  TextColumn get kind => textEnum<RecordKind>()();
  IntColumn get cursorUtcMs => integer()();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {deviceId, kind};
}

@DataClassName('SyncLockRow')
class SyncLocks extends Table {
  TextColumn get name => text()();
  TextColumn get owner => text()();
  IntColumn get acquiredAtUtcMs => integer()();
  IntColumn get expiresAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}
