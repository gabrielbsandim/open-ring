import 'package:drift/drift.dart';

@DataClassName('TrajectoryProjectionRow')
class TrajectoryProjections extends Table {
  TextColumn get monday => text()();
  RealColumn get trendKg => real()();
  RealColumn get rateKgPerWeek => real()();
  RealColumn get lowKg => real()();
  RealColumn get midKg => real()();
  RealColumn get highKg => real()();
  IntColumn get createdAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {monday};
}
