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
  BoolColumn get keepOnPhone => boolean().withDefault(const Constant(false))();
}

@DataClassName('MealAnalysisRow')
@TableIndex(
  name: 'meal_analyses_cache_key',
  columns: {#mealId, #providerHost, #model, #promptVersion},
  unique: true,
)
@TableIndex(name: 'meal_analyses_status', columns: {#status})
class MealAnalyses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get mealId =>
      integer().references(Meals, #id, onDelete: KeyAction.cascade)();
  TextColumn get photoName => text()();
  TextColumn get status => text()();
  TextColumn get providerHost => text()();
  TextColumn get model => text()();
  IntColumn get promptVersion => integer()();
  IntColumn get outputSchema => integer()();
  TextColumn get sentSha256 => text().nullable()();
  IntColumn get sentWidth => integer().nullable()();
  IntColumn get sentHeight => integer().nullable()();
  IntColumn get sentBytes => integer().nullable()();
  TextColumn get resultJson => text().nullable()();
  TextColumn get rawText => text().nullable()();
  TextColumn get confidence => text().nullable()();
  IntColumn get promptTokens => integer().nullable()();
  IntColumn get completionTokens => integer().nullable()();
  IntColumn get reasoningTokens => integer().nullable()();
  RealColumn get cost => real().nullable()();
  TextColumn get costCurrency => text().nullable()();
  TextColumn get costSource => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get errorKind => text().nullable()();
  BoolColumn get hiddenOil => boolean().withDefault(const Constant(false))();
  BoolColumn get hiddenSauce => boolean().withDefault(const Constant(false))();
  BoolColumn get hiddenSugar => boolean().withDefault(const Constant(false))();
  IntColumn get queuedAtUtcMs => integer()();
  IntColumn get updatedAtUtcMs => integer()();
}

@DataClassName('MealItemRow')
@TableIndex(name: 'meal_items_analysis', columns: {#analysisId})
class MealItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get analysisId =>
      integer().references(MealAnalyses, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get name => text()();
  TextColumn get measure => text()();
  IntColumn get countX2 => integer()();
  IntColumn get grams => integer()();
  TextColumn get origin => text()();
  BoolColumn get confirmed => boolean().withDefault(const Constant(false))();
}
