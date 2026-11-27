import 'package:drift/drift.dart';

@DataClassName('WeighInRow')
class WeighIns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get atUtcMs => integer()();
  IntColumn get offsetMinutes => integer()();
  RealColumn get kilograms => real()();
  RealColumn get bodyFatPercent => real().nullable()();
  RealColumn get waistCentimeters => real().nullable()();
  TextColumn get source => text()();
}
