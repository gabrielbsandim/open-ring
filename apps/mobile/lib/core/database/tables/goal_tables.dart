import 'package:drift/drift.dart';

@DataClassName('GoalRow')
class Goals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()();
  TextColumn get pace => text().nullable()();
  TextColumn get startedOn => text()();
  RealColumn get anchorKg => real().nullable()();
  RealColumn get referenceKg => real().nullable()();
  TextColumn get blockStartedOn => text()();
  RealColumn get blockAnchorKg => real().nullable()();
  TextColumn get phase => text()();
  TextColumn get phaseSince => text()();
  TextColumn get phaseUntil => text().nullable()();
  TextColumn get levers => text()();
  TextColumn get endedOn => text().nullable()();
  TextColumn get endReason => text().nullable()();
}

@DataClassName('GoalWeekRow')
class GoalWeeks extends Table {
  IntColumn get goalId =>
      integer().references(Goals, #id, onDelete: KeyAction.cascade)();
  TextColumn get monday => text()();
  TextColumn get inputs => text()();
  TextColumn get rule => text()();
  TextColumn get action => text()();
  TextColumn get change => text().nullable()();
  TextColumn get answer => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {goalId, monday};
}

@DataClassName('GoalScreeningRow')
class GoalScreenings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get askedOn => text()();
  BoolColumn get softMode => boolean().nullable()();
  BoolColumn get pregnantOrBreastfeeding => boolean().nullable()();
}
