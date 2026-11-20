import 'package:drift/drift.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';

final class DriftMealStore implements MealStore {
  new(this._db);

  final AppDatabase _db;

  @override
  Future<Meal> add(
    MealDraft draft, {
    required DateTime now,
    String? photo,
  }) async {
    if (photo != null) checkMealPhotoName(photo);
    final id = await _db
        .into(_db.meals)
        .insert(
          _companion(draft).copyWith(
            photo: Value(photo),
            createdAtUtcMs: Value(now.millisecondsSinceEpoch),
          ),
        );
    return _meal(await _row(id));
  }

  @override
  Future<bool> update(int id, MealDraft draft) async {
    final written = await (_db.update(
      _db.meals,
    )..where((row) => row.id.equals(id))).write(_companion(draft));
    return written > 0;
  }

  @override
  Future<bool> attachPhoto(int id, String name) async {
    checkMealPhotoName(name);
    final written =
        await (_db.update(_db.meals)..where((row) => row.id.equals(id))).write(
          MealsCompanion(photo: Value(name)),
        );
    return written > 0;
  }

  @override
  Future<Meal?> byId(int id) async {
    final row = await (_db.select(
      _db.meals,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    return row == null ? null : _meal(row);
  }

  @override
  Future<Meal?> delete(int id) => _db.transaction(() async {
    final row = await (_db.select(
      _db.meals,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    await (_db.delete(_db.meals)..where((row) => row.id.equals(id))).go();
    return _meal(row);
  });

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) async {
    if (from.compareTo(to) > 0) return const [];
    final wall =
        _db.meals.atUtcMs +
        _db.meals.offsetMinutes *
            const Constant(Duration.millisecondsPerMinute);
    final rows =
        await (_db.select(_db.meals)
              ..where(
                (_) =>
                    wall.isBiggerOrEqualValue(_foodDayStartMs(from)) &
                    wall.isSmallerThanValue(_foodDayStartMs(to.addDays(1))),
              )
              ..orderBy([
                (_) => OrderingTerm.asc(wall),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    return [for (final row in rows) _meal(row)];
  }

  @override
  Future<int> count() => _db.meals.count().getSingle();

  @override
  Future<int> clear() => _db.delete(_db.meals).go();

  @override
  Future<List<String>> deletePhotosBefore(DateTime cutoff) =>
      _db.transaction(() async {
        Expression<bool> released($MealsTable row) =>
            row.photo.isNotNull() &
            row.atUtcMs.isSmallerThanValue(cutoff.millisecondsSinceEpoch);
        final rows =
            await (_db.select(_db.meals)
                  ..where(released)
                  ..orderBy([
                    (row) => OrderingTerm.asc(row.atUtcMs),
                    (row) => OrderingTerm.asc(row.id),
                  ]))
                .get();
        await (_db.update(
          _db.meals,
        )..where(released)).write(const MealsCompanion(photo: Value(null)));
        return [for (final row in rows) ?row.photo];
      });

  Future<MealRow> _row(int id) =>
      (_db.select(_db.meals)..where((row) => row.id.equals(id))).getSingle();
}

// The wall clock milliseconds of a food day's start, as fields read in UTC.
int _foodDayStartMs(LocalDate day) => DateTime.utc(
  day.year,
  day.month,
  day.day,
  foodDayStartHour,
).millisecondsSinceEpoch;

MealsCompanion _companion(MealDraft draft) => MealsCompanion(
  atUtcMs: Value(draft.at.millisecondsSinceEpoch),
  offsetMinutes: Value(draft.offsetMinutes),
  kind: Value(draft.kind?.name),
  protein: Value(draft.tags.protein),
  caffeine: Value(draft.tags.caffeine),
  heavy: Value(draft.tags.heavy),
  fried: Value(draft.tags.fried),
  sugar: Value(draft.tags.sugar),
  veg: Value(draft.tags.veg?.name),
  alcohol: Value(draft.tags.alcohol?.name),
  processed: Value(draft.tags.processed?.name),
  place: Value(draft.tags.place?.name),
  lastMeal: Value(draft.last),
);

// An unknown name, only possible after a downgrade, reads as not tapped.
Meal _meal(MealRow row) => Meal(
  id: row.id,
  at: DateTime.fromMillisecondsSinceEpoch(row.atUtcMs, isUtc: true),
  offsetMinutes: row.offsetMinutes,
  kind: MealKind.values.asNameMap()[row.kind],
  tags: MealTags(
    protein: row.protein,
    caffeine: row.caffeine,
    heavy: row.heavy,
    fried: row.fried,
    sugar: row.sugar,
    veg: MealVeg.values.asNameMap()[row.veg],
    alcohol: MealAlcohol.values.asNameMap()[row.alcohol],
    processed: MealProcessed.values.asNameMap()[row.processed],
    place: MealPlace.values.asNameMap()[row.place],
  ),
  last: row.lastMeal,
  photo: row.photo,
  createdAt: DateTime.fromMillisecondsSinceEpoch(
    row.createdAtUtcMs,
    isUtc: true,
  ),
);
