import 'dart:math' as math;

import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/energy.dart';
import 'package:metrics/src/food_week.dart';
import 'package:metrics/src/local_date.dart';
import 'package:metrics/src/weight_trend.dart';

const foodEnergyKcalPerKg = 7700;
const foodEnergyWindowDays = 35;
const foodEnergyMinDays = 28;
const foodEnergyMinWeekDays = 5;
const foodEnergyMinWeighIns = 20;
const foodEnergyMinRingDays = 20;
const foodEnergyGoalHoldDays = 14;
const foodEnergyChangeBand = 150;
const foodEnergyChangeStep = 10;
const foodEnergyMinExpenditure = 800;
const foodEnergyLookbackWeeks = 4;

// Log kcal a hidden chip adds to a meal: 10 g soybean oil (TACO 884),
// 15 g sauce at 400 and 10 g refined sugar (TACO 387).
const foodEnergyOilKcal = 88;
const foodEnergySauceKcal = 60;
const foodEnergySugarKcal = 39;

/// Coarse groups the model picks per item; the per person factor absorbs a
/// stable bias in these densities, so log energy is never shown as kcal.
enum FoodGroup {
  grainCooked(128), // TACO 3, Arroz, tipo 1, cozido
  bread(300), // TACO 53, Pão, trigo, francês
  legumeCooked(76), // TACO 561, Feijão, carioca, cozido
  rootCooked(77), // TACO 88, Batata, doce, cozida
  vegetable(25), // TACO 100, Brócolis, cozido
  leafySalad(15), // TACO 157, Tomate, com semente, cru
  fruit(56), // TACO 222, Maçã, Fuji, com casca, crua
  poultry(159), // TACO 410, Frango, peito, sem pele, grelhado
  redMeat(219), // TACO 377, Carne, bovina, patinho, sem gordura, grelhado
  processedMeat(296), // TACO 423, Lingüiça, porco, grelhada
  fish(122), // TACO 301, Merluza, filé, assado
  egg(146), // TACO 488, Ovo, de galinha, inteiro, cozido/10minutos
  cheese(330), // TACO 463, Queijo, mozarela
  milkYogurt(
    61,
  ), // FDC SR Legacy 171265, Milk, whole, 3.25% (TACO 458 has none)
  friedSnack(283), // TACO 386, Coxinha de frango, frita
  mixedDish(150), // ours, stews and casseroles
  pizzaSandwich(260), // ours, FDC pizza and sandwiches
  sweet(400), // ours
  nutsSeeds(606), // TACO 558, Amendoim, torrado, salgado
  fatSauce(400), // ours
  sugaryDrink(40), // ours, soda and juice
  alcoholicDrink(60), // ours
  plainDrink(0), // ours, water, plain coffee and tea
  other(150); // ours

  new(this.kcalPer100g);

  final int kcalPer100g;
}

typedef FoodEnergyItem = ({FoodGroup group, int grams});

/// `target` is the `host|model|prompt|schema` key of the analysis behind
/// `logKcal`; both are null when the meal has no confirmed items.
typedef FoodEnergyMeal = ({MealEntry entry, double? logKcal, String? target});

typedef FoodEnergyDay = ({LocalDate date, double logKcal, Set<String> targets});

enum FoodEnergyHoldReason {
  modelChanged,
  goalStart,
  weighIns,
  days,
  ringDays,
  implausible,
}

enum FoodEnergyGapDirection { under, over, none }

enum FoodEnergyChangeDirection { less, more, none }

typedef FoodEnergyShown = ({int low, int high});

double mealLogKcal(
  Iterable<FoodEnergyItem> items, {
  bool oil = false,
  bool sauce = false,
  bool sugar = false,
}) {
  final eaten = items.fold<double>(
    0,
    (sum, item) => sum + item.grams * item.group.kcalPer100g / 100,
  );
  return eaten +
      (oil ? foodEnergyOilKcal : 0) +
      (sauce ? foodEnergySauceKcal : 0) +
      (sugar ? foodEnergySugarKcal : 0);
}

/// Null unless the food day is complete and every window meal has a log;
/// the factor can absorb a stable bias but not a missing meal.
FoodEnergyDay? foodEnergyDay(LocalDate date, List<FoodEnergyMeal> meals) {
  final day = [
    for (final meal in meals)
      if (foodDay(meal.entry.at) == date) meal,
  ];
  if (!day.any((meal) => meal.entry.last)) return null;
  var logKcal = 0.0;
  final targets = <String>{};
  for (final meal in day) {
    if (!opensWindow(meal.entry)) continue;
    final log = meal.logKcal;
    if (log == null) return null;
    logKcal += log;
    final target = meal.target;
    if (target != null) targets.add(target);
  }
  return (date: date, logKcal: logKcal, targets: targets);
}

final class FoodEnergyFigures {
  const new({
    required this.slopeKgPerDay,
    required this.balance,
    required this.logMean,
    required this.weekMean,
    required this.previousMean,
    required this.ringMean,
    required this.expenditureLog,
    required this.factorLow,
    required this.factorHigh,
    required this.weekLow,
    required this.weekHigh,
    required this.gapDirection,
    required this.gapLow,
    required this.gapHigh,
    required this.changeDirection,
    required this.changeLow,
    required this.changeHigh,
  });

  final double slopeKgPerDay;
  final double balance;
  final double logMean;
  final double weekMean;
  final double previousMean;
  final double ringMean;
  final double expenditureLog;
  final double factorLow;
  final double factorHigh;
  final int weekLow;
  final int weekHigh;
  final FoodEnergyGapDirection gapDirection;

  /// Percent from the low and high factor; positive means the log is under.
  final double gapLow;
  final double gapHigh;
  final FoodEnergyChangeDirection changeDirection;
  final double changeLow;
  final double changeHigh;

  /// Whole percent as the person reads it, null when there is no clear gap.
  FoodEnergyShown? get gapShown => switch (gapDirection) {
    FoodEnergyGapDirection.under => (
      low: gapLow.round(),
      high: gapHigh.round(),
    ),
    FoodEnergyGapDirection.over => (
      low: (-gapHigh).round(),
      high: (-gapLow).round(),
    ),
    FoodEnergyGapDirection.none => null,
  };

  FoodEnergyShown get changeShown =>
      (low: _toChangeStep(changeLow), high: _toChangeStep(changeHigh));
}

int _toChangeStep(double value) =>
    (value / foodEnergyChangeStep).round() * foodEnergyChangeStep;

FoodEnergyFigures foodEnergyFigures({
  required double slopeKgPerDay,
  required double logMean,
  required double weekMean,
  required double previousMean,
  required double ringMean,
}) {
  final balance = slopeKgPerDay * foodEnergyKcalPerKg;
  final expenditureLog = logMean - balance;
  final factorLow = (1 - energyDayMargin) * ringMean / expenditureLog;
  final factorHigh = (1 + energyDayMargin) * ringMean / expenditureLog;
  final week = energyRange(
    weekMean * ringMean / expenditureLog,
    energyDayMargin,
  );
  final gapLow = (1 - 1 / factorLow) * 100;
  final gapHigh = (1 - 1 / factorHigh) * 100;
  final difference = weekMean - previousMean;
  final a = difference * factorLow;
  final b = difference * factorHigh;
  final changeLow = math.min(a, b) - foodEnergyChangeBand;
  final changeHigh = math.max(a, b) + foodEnergyChangeBand;
  return FoodEnergyFigures(
    slopeKgPerDay: slopeKgPerDay,
    balance: balance,
    logMean: logMean,
    weekMean: weekMean,
    previousMean: previousMean,
    ringMean: ringMean,
    expenditureLog: expenditureLog,
    factorLow: factorLow,
    factorHigh: factorHigh,
    weekLow: week.low,
    weekHigh: week.high,
    gapDirection: _gapDirection(gapLow, gapHigh),
    gapLow: gapLow,
    gapHigh: gapHigh,
    changeDirection: _changeDirection(changeLow, changeHigh),
    changeLow: changeLow,
    changeHigh: changeHigh,
  );
}

FoodEnergyGapDirection _gapDirection(double low, double high) {
  if (low > 0) return FoodEnergyGapDirection.under;
  if (high < 0) return FoodEnergyGapDirection.over;
  return FoodEnergyGapDirection.none;
}

FoodEnergyChangeDirection _changeDirection(double low, double high) {
  if (high < 0) return FoodEnergyChangeDirection.less;
  if (low > 0) return FoodEnergyChangeDirection.more;
  return FoodEnergyChangeDirection.none;
}

final class FoodEnergyCounts {
  const new({
    required this.sunday,
    required this.days,
    required this.weekDays,
    required this.weighIns,
    required this.ringDays,
  });

  final LocalDate sunday;
  final int days;
  final int weekDays;
  final int weighIns;
  final int ringDays;
}

sealed class FoodEnergyResult {
  const new(this.counts);

  final FoodEnergyCounts counts;
}

final class FoodEnergyReady extends FoodEnergyResult {
  const new(super.counts, this.figures);

  final FoodEnergyFigures figures;
}

/// No new range this week; [last] is the newest ready week within
/// [foodEnergyLookbackWeeks] earlier Sundays, null while still building.
final class FoodEnergyHold extends FoodEnergyResult {
  const new(super.counts, this.reason, {this.last});

  final FoodEnergyHoldReason reason;
  final FoodEnergyReady? last;
}

/// [ring] holds only the on-record ring day totals.
FoodEnergyResult foodEnergyWeek({
  required LocalDate sunday,
  required List<FoodEnergyDay> days,
  required List<DailyValue> weighIns,
  required List<DailyValue> ring,
  LocalDate? goalBlockStart,
}) {
  final start = sunday.addDays(1 - foodEnergyWindowDays);
  final monday = sunday.addDays(-6);
  bool inWindow(LocalDate date) =>
      date.compareTo(start) >= 0 && date.compareTo(sunday) <= 0;
  final window = [
    for (final day in days)
      if (inWindow(day.date)) day,
  ];
  final week = [
    for (final day in window)
      if (day.date.compareTo(monday) >= 0) day,
  ];
  final before = [
    for (final day in window)
      if (day.date.compareTo(monday) < 0) day,
  ];
  final weights = dailyWeights([
    for (final weighIn in weighIns)
      if (inWindow(weighIn.date)) weighIn,
  ]);
  final ringDays = [
    for (final day in ring)
      if (inWindow(day.date) && day.value.isFinite) day.value,
  ];
  final counts = FoodEnergyCounts(
    sunday: sunday,
    days: window.length,
    weekDays: week.length,
    weighIns: weights.length,
    ringDays: ringDays.length,
  );
  final targets = {for (final day in window) ...day.targets};
  final reason = _holdReason(
    counts,
    targets: targets.length,
    goalDays: goalBlockStart == null ? null : sunday.daysSince(goalBlockStart),
  );
  if (reason != null) return FoodEnergyHold(counts, reason);
  final ringMean = _mean(ringDays);
  final figures = foodEnergyFigures(
    slopeKgPerDay: _slope(weights, start),
    logMean: _logMean(window),
    weekMean: _logMean(week),
    previousMean: _logMean(before),
    ringMean: ringMean,
  );
  final plausible =
      figures.expenditureLog >= foodEnergyMinExpenditure &&
      ringMean >= foodEnergyMinExpenditure;
  if (!plausible) {
    return FoodEnergyHold(counts, FoodEnergyHoldReason.implausible);
  }
  return FoodEnergyReady(counts, figures);
}

/// The week ending [latestSunday]; when it holds, the newest ready week of
/// the [foodEnergyLookbackWeeks] Sundays before it rides along as `last`.
FoodEnergyResult foodEnergyLatest({
  required LocalDate latestSunday,
  required List<FoodEnergyDay> days,
  required List<DailyValue> weighIns,
  required List<DailyValue> ring,
  LocalDate? goalBlockStart,
}) {
  FoodEnergyResult weekEnding(LocalDate sunday) => foodEnergyWeek(
    sunday: sunday,
    days: days,
    weighIns: weighIns,
    ring: ring,
    goalBlockStart: goalBlockStart,
  );
  final latest = weekEnding(latestSunday);
  if (latest is! FoodEnergyHold) return latest;
  for (var back = 1; back <= foodEnergyLookbackWeeks; back++) {
    final earlier = weekEnding(latestSunday.addDays(-7 * back));
    if (earlier is FoodEnergyReady) {
      return FoodEnergyHold(latest.counts, latest.reason, last: earlier);
    }
  }
  return latest;
}

FoodEnergyHoldReason? _holdReason(
  FoodEnergyCounts counts, {
  required int targets,
  required int? goalDays,
}) {
  if (targets > 1) return FoodEnergyHoldReason.modelChanged;
  if (goalDays != null && goalDays >= 0 && goalDays < foodEnergyGoalHoldDays) {
    return FoodEnergyHoldReason.goalStart;
  }
  if (counts.weighIns < foodEnergyMinWeighIns) {
    return FoodEnergyHoldReason.weighIns;
  }
  final fewDays =
      counts.days < foodEnergyMinDays ||
      counts.weekDays < foodEnergyMinWeekDays;
  if (fewDays) return FoodEnergyHoldReason.days;
  if (counts.ringDays < foodEnergyMinRingDays) {
    return FoodEnergyHoldReason.ringDays;
  }
  return null;
}

double _logMean(List<FoodEnergyDay> days) =>
    _mean([for (final day in days) day.logKcal]);

/// OLS of daily mean weight on days since [start], as `weightRate` fits it.
double _slope(List<DailyValue> weights, LocalDate start) {
  final xs = [for (final day in weights) day.date.daysSince(start).toDouble()];
  final ys = [for (final day in weights) day.value];
  final meanX = _mean(xs);
  final meanY = _mean(ys);
  var spread = 0.0;
  var together = 0.0;
  for (var i = 0; i < xs.length; i++) {
    spread += (xs[i] - meanX) * (xs[i] - meanX);
    together += (xs[i] - meanX) * (ys[i] - meanY);
  }
  return together / spread;
}

double _mean(List<double> values) =>
    values.reduce((a, b) => a + b) / values.length;
