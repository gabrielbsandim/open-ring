import 'package:drift/drift.dart';
import 'package:open_ring/core/database/tables/ring_tables.dart';
import 'package:ring_driver/ring_driver.dart';

@DataClassName('SleepSessionRow')
class SleepSessions extends Table {
  TextColumn get deviceId => text().references(RingDevices, #deviceId)();
  IntColumn get startUtcMs => integer()();
  IntColumn get endUtcMs => integer()();
  IntColumn get offsetMinutes => integer()();

  @override
  Set<Column<Object>> get primaryKey => {deviceId, startUtcMs};
}

@DataClassName('SleepSegmentRow')
class SleepSegments extends Table {
  TextColumn get deviceId => text().references(RingDevices, #deviceId)();
  IntColumn get startUtcMs => integer()();
  IntColumn get endUtcMs => integer()();
  IntColumn get offsetMinutes => integer()();
  TextColumn get stage => textEnum<SleepStage>()();
  IntColumn get sessionStartUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {deviceId, startUtcMs};
}
