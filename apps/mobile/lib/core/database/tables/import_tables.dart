import 'package:drift/drift.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:ring_driver/ring_driver.dart';

@DataClassName('ImportedSleepSessionRow')
class ImportedSleepSessions extends Table {
  TextColumn get recordId => text()();
  TextColumn get source => text()();
  IntColumn get startUtcMs => integer()();
  IntColumn get endUtcMs => integer()();
  IntColumn get offsetMinutes => integer()();
  IntColumn get importedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {recordId};
}

@DataClassName('ImportedSleepStageRow')
class ImportedSleepStages extends Table {
  TextColumn get recordId => text().references(
    ImportedSleepSessions,
    #recordId,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get startUtcMs => integer()();
  IntColumn get endUtcMs => integer()();
  TextColumn get stage => textEnum<SleepStage>()();

  @override
  Set<Column<Object>> get primaryKey => {recordId, startUtcMs};
}

@DataClassName('ImportedWorkoutRow')
class ImportedWorkouts extends Table {
  TextColumn get recordId => text()();
  TextColumn get source => text()();
  TextColumn get activityType => text()();
  IntColumn get startUtcMs => integer()();
  IntColumn get endUtcMs => integer()();
  IntColumn get offsetMinutes => integer()();
  IntColumn get importedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {recordId};
}

@DataClassName('HealthReadRow')
class HealthReads extends Table {
  TextColumn get kind => textEnum<HealthRecordKind>()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  IntColumn get lastReadAtUtcMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {kind};
}
