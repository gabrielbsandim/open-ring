import 'dart:math' as math;

import 'package:metrics/src/food_week.dart';
import 'package:metrics/src/local_date.dart';

/// Nights a comparison looks back over, ending at the last night.
const foodCompareNights = 90;

/// A control night is at most this many days from its exposed night.
const foodPairMaxDays = 10;

const alcoholMinPairs = 10;
const foodMinPairs = 14;

/// Last meal to sleep onset: under this is a late night.
const lateMealExposedMinutes = 120;

/// Last meal to sleep onset: at least this is a control night.
const lateMealControlMinutes = 180;

const int caffeineLateMinute = 14 * 60;

/// Smallest meaningful difference: bpm, percent and minutes.
const heartRateMeaningful = 2.0;
const hrvMeaningfulPercent = 5.0;
const onsetMeaningfulMinutes = 15.0;

const regularityDays = 14;
const regularityMinDays = 10;

enum FoodLink {
  alcoholThreeOrMore,
  alcoholOneToTwo,
  lateLastMeal,
  caffeineAfter14,
  heavyDinner,
}

/// Sleep stages never lead a comparison: only these three do.
enum NightOutcome { heartRate, hrv, onset }

/// One night, keyed by the food day it closes.
final class FoodNight {
  const new({required this.day, this.heartRate, this.hrv, this.sleepOnset});

  final LocalDate day;
  final double? heartRate;
  final double? hrv;

  /// Local wall clock.
  final DateTime? sleepOnset;
}

final class NightPair {
  const new({required this.exposed, required this.control});

  final LocalDate exposed;
  final LocalDate control;
}

sealed class LinkComparison {
  const new({required this.pairs});

  /// Pairs with the outcome on both nights.
  final int pairs;
}

final class LinkCollecting extends LinkComparison {
  const new({required super.pairs, required this.minimum});

  final int minimum;
}

/// Mean and 99% interval of exposed minus control: bpm, percent or minutes.
sealed class LinkDecided extends LinkComparison {
  const new({
    required super.pairs,
    required this.mean,
    required this.low,
    required this.high,
  });

  final double mean;
  final double low;
  final double high;
}

final class LinkPattern extends LinkDecided {
  const new({
    required super.pairs,
    required super.mean,
    required super.low,
    required super.high,
  });
}

final class LinkNoClearDifference extends LinkDecided {
  const new({
    required super.pairs,
    required super.mean,
    required super.low,
    required super.high,
  });
}

sealed class RegularityResult {
  const new({required this.completeDays});

  final int completeDays;
}

final class RegularityCollecting extends RegularityResult {
  const new({required super.completeDays, required this.minimum});

  final int minimum;
}

final class MealRegularity extends RegularityResult {
  const new({
    required super.completeDays,
    required this.firstMealSdMinutes,
    this.weekendLaterMinutes,
  });

  final double firstMealSdMinutes;

  /// Saturday and Sunday mean first meal minus the weekday mean, null when
  /// either side has no day.
  final double? weekendLaterMinutes;
}

/// Each exposed night, oldest first, takes the nearest free control night of
/// the same weekend kind; at equal distance the earlier night wins.
List<NightPair> matchPairs({
  required FoodLink link,
  required LocalDate lastNight,
  required List<FoodNight> nights,
  required List<MealEntry> meals,
}) {
  final days = _foodNights(lastNight, nights, meals);
  final exposure = {
    for (final MapEntry(key: day, value: night) in days.entries)
      day: _exposure(link, night),
  };
  final exposed = [
    for (final MapEntry(key: day, value: kind) in exposure.entries)
      if (kind == true) day,
  ]..sort((a, b) => a.compareTo(b));
  final used = <LocalDate>{};
  final pairs = <NightPair>[];
  for (final day in exposed) {
    final control = _nearestControl(day, exposure, used);
    if (control == null) continue;
    used.add(control);
    pairs.add(NightPair(exposed: day, control: control));
  }
  return pairs;
}

LinkComparison compareLink({
  required FoodLink link,
  required NightOutcome outcome,
  required LocalDate lastNight,
  required List<FoodNight> nights,
  required List<MealEntry> meals,
}) {
  final byDay = {for (final night in nights) night.day: night};
  final pairs = matchPairs(
    link: link,
    lastNight: lastNight,
    nights: nights,
    meals: meals,
  );
  final differences = [
    for (final pair in pairs)
      ?_difference(outcome, byDay[pair.exposed]!, byDay[pair.control]!),
  ];
  final n = differences.length;
  final minimum = _minimumPairs(link);
  if (n < minimum) return LinkCollecting(pairs: n, minimum: minimum);
  final mean = _mean(differences);
  final half = t99(n - 1) * _sd(differences, mean) / math.sqrt(n);
  final low = mean - half;
  final high = mean + half;
  double shown(double value) =>
      outcome == NightOutcome.hrv ? (math.exp(value) - 1) * 100 : value;
  final excludesZero = low > 0 || high < 0;
  if (excludesZero && shown(mean).abs() >= _meaningful(outcome)) {
    return LinkPattern(
      pairs: n,
      mean: shown(mean),
      low: shown(low),
      high: shown(high),
    );
  }
  return LinkNoClearDifference(
    pairs: n,
    mean: shown(mean),
    low: shown(low),
    high: shown(high),
  );
}

/// Two sided 99% Student t for [df] degrees of freedom.
double t99(int df) {
  if (df < 1) throw ArgumentError.value(df, 'df', 'must be at least 1');
  var low = 0.0;
  var high = 1000.0;
  for (var i = 0; i < 100; i++) {
    final mid = (low + high) / 2;
    if (_centralT(mid, df) < 0.99) {
      low = mid;
      continue;
    }
    high = mid;
  }
  return (low + high) / 2;
}

/// SD of the first meal time over the last 14 complete days, and how much
/// later it comes on Saturday and Sunday. Descriptive only.
RegularityResult mealRegularity({required List<MealEntry> meals}) {
  final first = <LocalDate, DateTime>{};
  final complete = <LocalDate>{};
  for (final meal in meals) {
    final day = foodDay(meal.at);
    if (meal.last) complete.add(day);
    if (!opensWindow(meal)) continue;
    final earliest = first[day];
    if (earliest != null && !meal.at.isBefore(earliest)) continue;
    first[day] = meal.at;
  }
  final days = [
    for (final day in complete)
      if (first.containsKey(day)) day,
  ]..sort((a, b) => a.compareTo(b));
  final recent = days.skip(math.max(0, days.length - regularityDays)).toList();
  if (recent.length < regularityMinDays) {
    return RegularityCollecting(
      completeDays: recent.length,
      minimum: regularityMinDays,
    );
  }
  final minutes = [for (final day in recent) _foodDayMinute(first[day]!)];
  final weekend = [
    for (final (i, day) in recent.indexed)
      if (_weekday(day) >= DateTime.saturday) minutes[i],
  ];
  final weekdays = [
    for (final (i, day) in recent.indexed)
      if (_weekday(day) < DateTime.saturday) minutes[i],
  ];
  final hasBoth = weekend.isNotEmpty && weekdays.isNotEmpty;
  return MealRegularity(
    completeDays: recent.length,
    firstMealSdMinutes: _sd(minutes, _mean(minutes)),
    weekendLaterMinutes: hasBoth ? _mean(weekend) - _mean(weekdays) : null,
  );
}

final class _FoodNight {
  new(this.night);

  final FoodNight night;
  bool complete = false;
  MealAlcohol? alcohol;
  bool caffeineLate = false;
  bool heavyDinner = false;
  DateTime? lastOpening;

  Duration? get gapToSleep {
    final onset = night.sleepOnset;
    final last = lastOpening;
    if (onset == null || last == null) return null;
    return onset.difference(last);
  }
}

Map<LocalDate, _FoodNight> _foodNights(
  LocalDate lastNight,
  List<FoodNight> nights,
  List<MealEntry> meals,
) {
  final first = lastNight.addDays(1 - foodCompareNights);
  final days = {
    for (final night in nights)
      if (night.day.compareTo(first) >= 0 &&
          night.day.compareTo(lastNight) <= 0)
        night.day: _FoodNight(night),
  };
  for (final meal in meals) {
    final day = days[foodDay(meal.at)];
    if (day == null) continue;
    _addMeal(day, meal);
  }
  return days;
}

void _addMeal(_FoodNight day, MealEntry meal) {
  final tags = meal.tags;
  if (meal.last) day.complete = true;
  if (tags.alcohol case final alcohol?) {
    day.alcohol = alcohol == MealAlcohol.threeOrMore
        ? alcohol
        : day.alcohol ?? alcohol;
  }
  if (tags.caffeine && _foodDayMinute(meal.at) >= caffeineLateMinute) {
    day.caffeineLate = true;
  }
  final slot = mealSlot(meal.at);
  if (tags.heavy && (slot == MealSlot.dinner || slot == MealSlot.supper)) {
    day.heavyDinner = true;
  }
  if (!opensWindow(meal)) return;
  final last = day.lastOpening;
  if (last != null && !meal.at.isAfter(last)) return;
  day.lastOpening = meal.at;
}

// True for an exposed night, false for a control, null for neither. Every
// link keeps alcohol nights out of its controls.
bool? _exposure(FoodLink link, _FoodNight day) {
  if (!day.complete) return null;
  final alcohol = day.alcohol;
  return switch (link) {
    FoodLink.alcoholThreeOrMore => _alcoholExposure(
      alcohol,
      MealAlcohol.threeOrMore,
    ),
    FoodLink.alcoholOneToTwo => _alcoholExposure(alcohol, MealAlcohol.oneToTwo),
    _ when alcohol != null => null,
    FoodLink.lateLastMeal => _lateExposure(day.gapToSleep),
    FoodLink.caffeineAfter14 => day.caffeineLate,
    FoodLink.heavyDinner => day.heavyDinner,
  };
}

bool? _alcoholExposure(MealAlcohol? alcohol, MealAlcohol dose) {
  if (alcohol == null) return false;
  if (alcohol == dose) return true;
  return null;
}

bool? _lateExposure(Duration? gap) {
  if (gap == null) return null;
  if (gap < const Duration(minutes: lateMealExposedMinutes)) return true;
  if (gap >= const Duration(minutes: lateMealControlMinutes)) return false;
  return null;
}

LocalDate? _nearestControl(
  LocalDate day,
  Map<LocalDate, bool?> exposure,
  Set<LocalDate> used,
) {
  for (var distance = 1; distance <= foodPairMaxDays; distance++) {
    for (final candidate in [day.addDays(-distance), day.addDays(distance)]) {
      if (exposure[candidate] != false || used.contains(candidate)) continue;
      if (_weekendNight(candidate) != _weekendNight(day)) continue;
      return candidate;
    }
  }
  return null;
}

int _weekday(LocalDate day) =>
    DateTime.utc(day.year, day.month, day.day).weekday;

/// A Friday or Saturday evening.
bool _weekendNight(LocalDate day) =>
    _weekday(day) == DateTime.friday || _weekday(day) == DateTime.saturday;

/// Minutes from midnight of the food day, so 00:30 the next morning is 1470.
double _foodDayMinute(DateTime local) {
  final minutes = local.hour * 60 + local.minute + local.second / 60;
  if (local.hour < foodDayStartHour) return minutes + Duration.minutesPerDay;
  return minutes;
}

double? _difference(
  NightOutcome outcome,
  FoodNight exposed,
  FoodNight control,
) {
  final a = _value(outcome, exposed);
  final b = _value(outcome, control);
  if (a == null || b == null) return null;
  return a - b;
}

// HRV in logs, so the mean reads as a percent; 0 ms is no reading.
double? _value(NightOutcome outcome, FoodNight night) => switch (outcome) {
  NightOutcome.heartRate => night.heartRate,
  NightOutcome.hrv => _logHrv(night.hrv),
  NightOutcome.onset => _onsetMinute(night),
};

double? _logHrv(double? hrv) {
  if (hrv == null || hrv <= 0) return null;
  return math.log(hrv);
}

double? _onsetMinute(FoodNight night) {
  final onset = night.sleepOnset;
  if (onset == null) return null;
  final date = LocalDate(onset.year, onset.month, onset.day);
  final days = date.daysSince(night.day);
  return days * Duration.minutesPerDay +
      onset.hour * 60 +
      onset.minute +
      onset.second / 60;
}

int _minimumPairs(FoodLink link) => switch (link) {
  FoodLink.alcoholThreeOrMore || FoodLink.alcoholOneToTwo => alcoholMinPairs,
  _ => foodMinPairs,
};

double _meaningful(NightOutcome outcome) => switch (outcome) {
  NightOutcome.heartRate => heartRateMeaningful,
  NightOutcome.hrv => hrvMeaningfulPercent,
  NightOutcome.onset => onsetMeaningfulMinutes,
};

double _mean(List<double> values) =>
    values.fold<double>(0, (sum, value) => sum + value) / values.length;

double _sd(List<double> values, double mean) {
  final squares = values.fold<double>(
    0,
    (sum, value) => sum + (value - mean) * (value - mean),
  );
  return math.sqrt(squares / (values.length - 1));
}

// P(|T| < t) for integer df, Abramowitz and Stegun 26.7.3 and 26.7.4.
double _centralT(double t, int df) {
  final theta = math.atan(t / math.sqrt(df));
  final cos2 = math.pow(math.cos(theta), 2).toDouble();
  final odd = df.isOdd;
  var term = 1.0;
  var sum = 1.0;
  for (var k = odd ? 3 : 2; k < df; k += 2) {
    term *= cos2 * (k - 1) / k;
    sum += term;
  }
  if (!odd) return math.sin(theta) * sum;
  if (df == 1) return 2 * theta / math.pi;
  return 2 / math.pi * (theta + math.sin(theta) * math.cos(theta) * sum);
}
