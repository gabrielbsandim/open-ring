import 'package:drift/drift.dart';
import 'package:open_ring/core/records/health_record_kind.dart';

@DataClassName('HealthOutboxRow')
class HealthOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => textEnum<HealthRecordKind>()();
  TextColumn get deviceId => text().nullable()();
  IntColumn get fromUtcMs => integer()();
  IntColumn get toUtcMs => integer()();
  IntColumn get recordCount => integer()();
  IntColumn get enqueuedAtUtcMs => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  IntColumn get completedAtUtcMs => integer().nullable()();
  TextColumn get status => textEnum<OutboxStatus>().withDefault(
    Constant(OutboxStatus.pending.name),
  )();
  IntColumn get lastAttemptAtUtcMs => integer().nullable()();
  IntColumn get nextAttemptAtUtcMs => integer().nullable()();
}

@DataClassName('SourcePriorityRow')
class SourcePriorities extends Table {
  TextColumn get metric => text()();
  TextColumn get source => text()();
  IntColumn get priority => integer()();

  @override
  Set<Column<Object>> get primaryKey => {metric, source};
}

@DataClassName('UserProfileRow')
class UserProfile extends Table {
  IntColumn get id => integer()
      .withDefault(const Constant(1))
      .check(const CustomExpression<bool>('id = 1'))();
  IntColumn get birthYear => integer().nullable()();
  TextColumn get sex => text().nullable()();
  RealColumn get heightCentimeters => real().nullable()();
  RealColumn get weightKilograms => real().nullable()();
  IntColumn get maxHeartRate => integer().nullable()();
  IntColumn get dailyStepGoal => integer().nullable()();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
