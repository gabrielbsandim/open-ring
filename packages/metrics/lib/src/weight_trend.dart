import 'dart:math' as math;

import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/local_date.dart';

const weightTrendAlpha = 0.1;
const weightTrendSeedDays = 7;
const weightRateWindowDays = 28;
const weightRateMinDays = 8;
const weightRateMinSpanDays = 14;
const weightNoiseMinDays = 3;
const weightNoiseDefault = 0.5;
const weightNoiseFloor = 0.35;

const int _firstDegreesOfFreedom = weightRateMinDays - 2;

// Two sided 95 percent Student t quantiles, from 6 to 26 degrees of freedom:
// every size the 28 day window can produce.
const _studentT95 = [
  2.447,
  2.365,
  2.306,
  2.262,
  2.228,
  2.201,
  2.179,
  2.160,
  2.145,
  2.131,
  2.120,
  2.110,
  2.101,
  2.093,
  2.086,
  2.080,
  2.074,
  2.069,
  2.064,
  2.060,
  2.056,
];

sealed class WeightRate {
  const new();
}

final class WeightRateBuilding extends WeightRate {
  const new({required this.daysMissing, required this.spanMissing});

  final int daysMissing;
  final int spanMissing;
}

final class WeightRateReady extends WeightRate {
  const new({required this.perWeek, required this.low, required this.high});

  final double perWeek;
  final double low;
  final double high;

  bool get stable => low <= 0 && high >= 0;
}

List<DailyValue> dailyWeights(Iterable<DailyValue> weighIns) {
  final byDate = <LocalDate, List<double>>{};
  for (final weighIn in weighIns) {
    if (!weighIn.value.isFinite) continue;
    byDate.putIfAbsent(weighIn.date, () => []).add(weighIn.value);
  }
  return [
    for (final entry in byDate.entries)
      (date: entry.key, value: _mean(entry.value)),
  ]..sort((a, b) => a.date.compareTo(b.date));
}

List<DailyValue> weightTrend(Iterable<DailyValue> weighIns) {
  final daily = dailyWeights(weighIns);
  if (daily.isEmpty) return const [];
  var trend = _mean([
    for (final day in daily.take(weightTrendSeedDays)) day.value,
  ]);
  final out = [(date: daily.first.date, value: trend)];
  for (var i = 1; i < daily.length; i++) {
    final gap = daily[i].date.daysSince(daily[i - 1].date);
    final pull = 1 - math.pow(1 - weightTrendAlpha, gap).toDouble();
    trend += pull * (daily[i].value - trend);
    out.add((date: daily[i].date, value: trend));
  }
  return out;
}

WeightRate weightRate(
  Iterable<DailyValue> weighIns, {
  required LocalDate today,
}) {
  final window = [
    for (final day in dailyWeights(weighIns))
      if (_inRateWindow(today.daysSince(day.date))) day,
  ];
  final span = window.isEmpty
      ? 0
      : window.last.date.daysSince(window.first.date);
  if (window.length < weightRateMinDays || span < weightRateMinSpanDays) {
    return WeightRateBuilding(
      daysMissing: math.max(0, weightRateMinDays - window.length),
      spanMissing: math.max(0, weightRateMinSpanDays - span),
    );
  }
  final days = [
    for (final day in window) day.date.daysSince(window.first.date).toDouble(),
  ];
  final weights = [for (final day in window) day.value];
  final meanDay = _mean(days);
  final meanWeight = _mean(weights);
  var spread = 0.0;
  var together = 0.0;
  for (var i = 0; i < days.length; i++) {
    spread += (days[i] - meanDay) * (days[i] - meanDay);
    together += (days[i] - meanDay) * (weights[i] - meanWeight);
  }
  final slope = together / spread;
  var residual = 0.0;
  for (var i = 0; i < days.length; i++) {
    final miss = weights[i] - (meanWeight + slope * (days[i] - meanDay));
    residual += miss * miss;
  }
  final freedom = window.length - 2;
  final error = math.sqrt(residual / freedom / spread);
  final margin = _studentT95[freedom - _firstDegreesOfFreedom] * error;
  return WeightRateReady(
    perWeek: slope * 7,
    low: (slope - margin) * 7,
    high: (slope + margin) * 7,
  );
}

double weightNoise(Iterable<DailyValue> weighIns) {
  final daily = dailyWeights(weighIns);
  if (daily.length < weightNoiseMinDays) return weightNoiseDefault;
  final trend = weightTrend(daily);
  var sum = 0.0;
  for (var i = 0; i < daily.length; i++) {
    final miss = daily[i].value - trend[i].value;
    sum += miss * miss;
  }
  return math.max(weightNoiseFloor, math.sqrt(sum / daily.length));
}

bool _inRateWindow(int age) => age >= 0 && age < weightRateWindowDays;

double _mean(List<double> values) =>
    values.reduce((a, b) => a + b) / values.length;
