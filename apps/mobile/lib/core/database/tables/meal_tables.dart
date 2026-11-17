import 'package:drift/drift.dart';

@DataClassName('MealRow')
class Meals extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get atUtcMs => integer()();
  IntColumn get offsetMinutes => integer()();
  TextColumn get kind => text().nullable()();
  BoolColumn get protein => boolean().withDefault(const Constant(false))();
  BoolColumn get caffeine => boolean().withDefault(const Constant(false))();
  BoolColumn get heavy => boolean().withDefault(const Constant(false))();
  BoolColumn get fried => boolean().withDefault(const Constant(false))();
  BoolColumn get sugar => boolean().withDefault(const Constant(false))();
  TextColumn get veg => text().nullable()();
  TextColumn get alcohol => text().nullable()();
  TextColumn get processed => text().nullable()();
  TextColumn get place => text().nullable()();
  // `last` would clash with NULLS LAST in SQL.
  BoolColumn get lastMeal => boolean().withDefault(const Constant(false))();
  TextColumn get photo => text().nullable().unique()();
  IntColumn get createdAtUtcMs => integer()();
}
