import 'package:metrics/src/local_date.dart';

/// Food day start (docs/metrics.md, Food): a meal before 05:00 local closes
/// the evening before.
const foodDayStartHour = 5;

/// Plate pattern needs a closed week with this many complete days and mains.
const plateMinCompleteDays = 5;
const plateMinMains = 10;

/// Drinks a dose tag counts for in the Plate pattern.
const plateDrinksOneToTwo = 1.5;
const plateDrinksThreeOrMore = 4.0;

enum MealKind { main, snack, drink }

enum MealSlot { breakfast, lunch, afternoonSnack, dinner, supper }

enum MealVeg { some, halfOrMore }

enum MealAlcohol { oneToTwo, threeOrMore }

enum MealProcessed { mostly, unsure }

enum MealPlace { home, restaurant, packaged }

final class MealTags {
  const new({
    this.protein = false,
    this.caffeine = false,
    this.heavy = false,
    this.fried = false,
    this.sugar = false,
    this.veg,
    this.alcohol,
    this.processed,
    this.place,
  });

  final bool protein;
  final bool caffeine;
  final bool heavy;
  final bool fried;
  final bool sugar;
  final MealVeg? veg;
  final MealAlcohol? alcohol;
  final MealProcessed? processed;
  final MealPlace? place;

  bool get isEmpty =>
      !protein &&
      !caffeine &&
      !heavy &&
      !fried &&
      !sugar &&
      veg == null &&
      alcohol == null &&
      processed == null &&
      place == null;
}

final class MealEntry {
  const new({
    required this.at,
    this.kind,
    this.tags = const MealTags(),
    this.last = false,
  });

  /// Local wall clock capture time.
  final DateTime at;
  final MealKind? kind;
  final MealTags tags;
  final bool last;

  bool get tagged => kind != null || !tags.isEmpty;
}

final class FoodWeek {
  const new({
    required this.completeDays,
    required this.records,
    this.windowMinutes,
    this.gapMinutes,
  });

  final int completeDays;
  final int records;

  /// Median eating window over complete days, null when none has one.
  final double? windowMinutes;

  /// Median last meal to sleep onset over complete days with an onset.
  final double? gapMinutes;
}

sealed class PlateResult {
  const new({required this.completeDays, required this.mains});

  final int completeDays;
  final int mains;
}

final class PlateBuilding extends PlateResult {
  const new({required super.completeDays, required super.mains});
}

final class PlatePattern extends PlateResult {
  const new({
    required super.completeDays,
    required super.mains,
    required this.score,
    required this.points,
    required this.protein,
    required this.veg,
    required this.processed,
    required this.sugaryDays,
    required this.drinks,
  });

  /// 0 to 10, one decimal.
  final double score;

  /// Protein, veg, processed, sugar and drinks points, in that order.
  final List<double> points;
  final int protein;
  final int veg;
  final int processed;
  final int sugaryDays;
  final double drinks;
}

LocalDate foodDay(DateTime local) {
  final day = LocalDate(local.year, local.month, local.day);
  if (local.hour < foodDayStartHour) return day.addDays(-1);
  return day;
}

MealSlot mealSlot(DateTime local) {
  final minutes = local.hour * 60 + local.minute;
  if (minutes < foodDayStartHour * 60) return MealSlot.supper;
  if (minutes < 10 * 60 + 30) return MealSlot.breakfast;
  if (minutes < 15 * 60) return MealSlot.lunch;
  if (minutes < 18 * 60) return MealSlot.afternoonSnack;
  if (minutes < 23 * 60) return MealSlot.dinner;
  return MealSlot.supper;
}

/// A drink with no sugar and no alcohol neither opens nor closes the window.
bool opensWindow(MealEntry meal) =>
    meal.kind != MealKind.drink || meal.tags.sugar || meal.tags.alcohol != null;

FoodWeek foodWeek({
  required LocalDate monday,
  required List<MealEntry> meals,
  required Map<LocalDate, DateTime> sleepOnsets,
}) {
  final days = _completeDays(monday, meals);
  final windows = <double>[];
  final gaps = <double>[];
  for (final MapEntry(key: day, value: dayMeals) in days.complete.entries) {
    final opening = [
      for (final meal in dayMeals)
        if (opensWindow(meal)) meal.at,
    ]..sort();
    if (opening.isEmpty) continue;
    windows.add(_minutes(opening.last.difference(opening.first)));
    final onset = sleepOnsets[day];
    if (onset == null) continue;
    gaps.add(_minutes(onset.difference(opening.last)));
  }
  return FoodWeek(
    completeDays: days.complete.length,
    records: days.records,
    windowMinutes: _median(windows),
    gapMinutes: _median(gaps),
  );
}

PlateResult platePattern({
  required LocalDate monday,
  required List<MealEntry> meals,
}) {
  final days = _completeDays(monday, meals).complete;
  final eaten = [for (final dayMeals in days.values) ...dayMeals];
  final mains = [
    for (final meal in eaten)
      if (meal.kind == MealKind.main) meal.tags,
  ];
  final complete = days.length;
  if (complete < plateMinCompleteDays || mains.length < plateMinMains) {
    return PlateBuilding(completeDays: complete, mains: mains.length);
  }
  final protein = mains.where((tags) => tags.protein).length;
  final veg = mains.where((tags) => tags.veg != null).length;
  final processed = mains
      .where((tags) => tags.processed == MealProcessed.mostly)
      .length;
  final sugaryDays = days.values
      .where((dayMeals) => dayMeals.any((meal) => meal.tags.sugar))
      .length;
  final drinks = eaten.fold<double>(0, (sum, meal) => sum + _drinks(meal.tags));
  final share = mains.length.toDouble();
  final perWeek = 7 / complete;
  final points = [
    3 * _ramp(protein / share, 0.3, 0.9),
    3 * _ramp(veg / share, 0.2, 0.8),
    2 * _ramp(1 - processed / share, 0.4, 0.9),
    _ramp(sugaryDays * perWeek, 4, 0),
    _ramp(drinks * perWeek, 10, 2),
  ];
  final sum = points.fold<double>(0, (total, point) => total + point);
  return PlatePattern(
    completeDays: complete,
    mains: mains.length,
    score: (sum * 10).round() / 10,
    points: List.unmodifiable(points),
    protein: protein,
    veg: veg,
    processed: processed,
    sugaryDays: sugaryDays,
    drinks: drinks,
  );
}

({Map<LocalDate, List<MealEntry>> complete, int records}) _completeDays(
  LocalDate monday,
  List<MealEntry> meals,
) {
  final byDay = <LocalDate, List<MealEntry>>{};
  for (final meal in meals) {
    final offset = foodDay(meal.at).daysSince(monday);
    if (offset < 0 || offset > 6) continue;
    (byDay[foodDay(meal.at)] ??= []).add(meal);
  }
  final records = byDay.values.fold(0, (sum, day) => sum + day.length);
  byDay.removeWhere((_, dayMeals) => !dayMeals.any((meal) => meal.last));
  return (complete: byDay, records: records);
}

double _drinks(MealTags tags) => switch (tags.alcohol) {
  null => 0,
  MealAlcohol.oneToTwo => plateDrinksOneToTwo,
  MealAlcohol.threeOrMore => plateDrinksThreeOrMore,
};

/// 0 at [zero], 1 at [full], linear between and clamped; [full] may be lower.
double _ramp(double value, double zero, double full) =>
    ((value - zero) / (full - zero)).clamp(0, 1).toDouble();

double _minutes(Duration span) =>
    span.inMicroseconds / Duration.microsecondsPerMinute;

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}
