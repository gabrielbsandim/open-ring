import 'package:drift/drift.dart';

@DataClassName('DayTagRow')
class DayTags extends Table {
  TextColumn get date => text()();
  TextColumn get tag => text()();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {date};
}
