import 'dart:math' as math;

import 'package:metrics/src/goal_rate.dart';
import 'package:metrics/src/weight_trend.dart';

const trajectoryAdaptationDays = 365.0;
const trajectoryFirmDays = 28;
const trajectoryBandDays = 84;
const trajectoryFastLossPercent = 1.0;

final class ScenarioBand {
  const new({
    required this.days,
    required this.low,
    required this.mid,
    required this.high,
  });

  final int days;
  final double low;
  final double mid;
  final double high;
}

// The burn falls as weight changes, so the rate bends toward a plateau instead
// of running on as a straight line.
double scenarioDays(int days) {
  if (days < 0) {
    throw ArgumentError.value(days, 'days', 'must not be negative');
  }
  return trajectoryAdaptationDays *
      (1 - math.exp(-days / trajectoryAdaptationDays));
}

ScenarioBand weightScenario(
  double trendKg,
  WeightRateReady rate,
  double noiseKg,
  int days,
) {
  if (noiseKg < 0) {
    throw ArgumentError.value(noiseKg, 'noiseKg', 'must not be negative');
  }
  final weeks = scenarioDays(days) / 7;
  return ScenarioBand(
    days: days,
    low: trendKg + rate.low * weeks - noiseKg,
    mid: trendKg + rate.perWeek * weeks,
    high: trendKg + rate.high * weeks + noiseKg,
  );
}

bool fastLossGuard(LossRate rate) => overCap(rate, trajectoryFastLossPercent);
