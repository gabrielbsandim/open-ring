import 'dart:math' as math;

import 'package:metrics/src/goal_rate.dart';
import 'package:metrics/src/overall_score.dart';
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

/// The band with every edge held at the BMI [bmiFloor] weight for
/// [heightCm], but never above [trendKg], so a trend already under the floor
/// is not pushed up.
ScenarioBand scenarioFloored(
  ScenarioBand band, {
  required double trendKg,
  required double heightCm,
}) {
  final meters = heightCm / 100;
  final floor = math.min(bmiFloor * meters * meters, trendKg);
  return ScenarioBand(
    days: band.days,
    low: math.max(band.low, floor),
    mid: math.max(band.mid, floor),
    high: math.max(band.high, floor),
  );
}

bool fastLossGuard(LossRate rate) => overCap(rate, trajectoryFastLossPercent);
