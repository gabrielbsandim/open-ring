import 'dart:math' as math;

import 'package:metrics/src/local_date.dart';

typedef DailyValue = ({LocalDate date, double value});

typedef HrvReading = ({DateTime at, int milliseconds});

enum BaselineScale { linear, log }

const baselineWindowDays = 28;
const baselineMinDays = 7;
const hrvMinLogSpread = 0.05;
const restingHeartRateMinSpread = 1.0;
const nightlyHrvMinReadings = 3;

sealed class BaselineResult {
  const new();
}

final class BaselineBuilding extends BaselineResult {
  const new({required this.daysCollected, required this.daysNeeded});

  final int daysCollected;
  final int daysNeeded;
}

final class BaselineReady extends BaselineResult {
  const new({
    required this.scale,
    required this.meanOnScale,
    required this.sdOnScale,
    required this.days,
  });

  final BaselineScale scale;

  final double meanOnScale;
  final double sdOnScale;
  final int days;

  double get typical => switch (scale) {
    BaselineScale.linear => meanOnScale,
    BaselineScale.log => math.exp(meanOnScale),
  };

  BaselineDeviation compare(double today) {
    if (scale == BaselineScale.log && today <= 0) {
      throw ArgumentError.value(today, 'today', 'must be positive');
    }
    final onScale = switch (scale) {
      BaselineScale.linear => today,
      BaselineScale.log => math.log(today),
    };
    return BaselineDeviation(
      today: today,
      baseline: typical,
      zScore: (onScale - meanOnScale) / sdOnScale,
    );
  }
}

final class BaselineDeviation {
  const new({
    required this.today,
    required this.baseline,
    required this.zScore,
  });

  final double today;
  final double baseline;
  final double zScore;

  double get delta => today - baseline;

  double get percent => (today / baseline - 1) * 100;
}

BaselineResult personalBaseline(
  Iterable<DailyValue> history, {
  required LocalDate today,
  BaselineScale scale = BaselineScale.linear,
  double minSpread = 0,
  int windowDays = baselineWindowDays,
  int minDays = baselineMinDays,
}) {
  if (windowDays < 1) {
    throw ArgumentError.value(windowDays, 'windowDays', 'must be at least 1');
  }
  if (minDays < 2 || minDays > windowDays) {
    throw ArgumentError.value(minDays, 'minDays', 'must be in 2..windowDays');
  }
  final byDate = <LocalDate, double>{};
  for (final d in history) {
    final age = today.daysSince(d.date);
    if (age < 1 || age > windowDays) continue;
    if (!_usable(d.value, scale)) continue;
    byDate[d.date] = d.value;
  }
  if (byDate.length < minDays) {
    return BaselineBuilding(daysCollected: byDate.length, daysNeeded: minDays);
  }
  final values = [
    for (final v in byDate.values)
      if (scale == BaselineScale.log) math.log(v) else v,
  ];
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance =
      values.fold<double>(0, (sum, v) => sum + (v - mean) * (v - mean)) /
      (values.length - 1);
  return BaselineReady(
    scale: scale,
    meanOnScale: mean,
    sdOnScale: math.max(math.sqrt(variance), minSpread),
    days: values.length,
  );
}

bool _usable(double value, BaselineScale scale) {
  if (!value.isFinite) return false;
  return scale == BaselineScale.linear || value > 0;
}

BaselineResult hrvBaseline(
  Iterable<DailyValue> nightlyHrv, {
  required LocalDate today,
}) => personalBaseline(
  nightlyHrv,
  today: today,
  scale: BaselineScale.log,
  minSpread: hrvMinLogSpread,
);

BaselineResult restingHeartRateBaseline(
  Iterable<DailyValue> nightlyRestingHeartRate, {
  required LocalDate today,
}) => personalBaseline(
  nightlyRestingHeartRate,
  today: today,
  minSpread: restingHeartRateMinSpread,
);

double? nightlyHrv(
  Iterable<HrvReading> readings, {
  int minReadings = nightlyHrvMinReadings,
}) {
  if (minReadings < 1) {
    throw ArgumentError.value(minReadings, 'minReadings', 'must be at least 1');
  }
  // A zero is a slot the ring could not measure, not a reading.
  final valid = [
    for (final r in readings)
      if (r.milliseconds > 0) r.milliseconds,
  ];
  if (valid.length < minReadings) return null;
  return valid.reduce((a, b) => a + b) / valid.length;
}
