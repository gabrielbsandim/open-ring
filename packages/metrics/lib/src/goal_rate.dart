import 'dart:math' as math;

import 'package:metrics/src/local_date.dart';
import 'package:metrics/src/overall_score.dart';
import 'package:metrics/src/weight_trend.dart';

const goalStandardPercent = 0.5;
const goalGentlePercent = 0.25;
const goalCapBmiMid = 25.0;
const goalCapBmiHigh = 30.0;
const goalBlockWeeks = 12;
const goalBlockMaxLossPercent = 10.0;
const goalMaintenanceWeeks = 4;
const goalBandLow = 0.5;
const goalBandHigh = 1.5;
const goalArrivalMaxBlocks = 6;
const goalReferenceStepKg = 0.5;
const goalMinAge = 18;
const goalSoftModeYes = 2;

enum GoalKind { loseFat, getFitter, sleepBetter }

enum GoalPace { standard, gentle }

enum PathState { building, above, onTrack, below }

enum WeightGoalRefusal {
  ageMissing,
  under18,
  heightMissing,
  pregnancy,
  bmiUnderFloor,
}

final class GoalBlock {
  const new({
    required this.start,
    required this.weeks,
    required this.weeklyKg,
    required this.blockKg,
    required this.end,
    required this.maintenanceEnd,
    required this.anchorKg,
  });

  final LocalDate start;
  final int weeks;
  final double weeklyKg;
  final double blockKg;
  final LocalDate end;
  final LocalDate maintenanceEnd;

  /// The trend weight the block started from.
  final double anchorKg;
}

/// A block closes at the first Monday after its last day, or at a Monday
/// whose trend has lost [goalBlockMaxLossPercent] of the anchor.
bool blockCloses({
  required GoalBlock block,
  required LocalDate monday,
  required double? trendKg,
}) {
  if (monday.compareTo(block.end) > 0) return true;
  if (trendKg == null) return false;
  final lost = block.anchorKg - trendKg;
  return lost >= block.anchorKg * goalBlockMaxLossPercent / 100;
}

// A loss is positive here, the opposite sign of the weight slope.
final class LossRate {
  const new({
    required this.kg,
    required this.kgLow,
    required this.kgHigh,
    required this.percent,
    required this.percentLow,
    required this.percentHigh,
  });

  final double kg;
  final double kgLow;
  final double kgHigh;
  final double percent;
  final double percentLow;
  final double percentHigh;
}

final class ArrivalRange {
  const new({
    required this.earliest,
    required this.latest,
    required this.earliestWeeks,
    required this.latestWeeks,
  });

  final LocalDate earliest;
  final LocalDate latest;
  final double earliestWeeks;
  final double latestWeeks;
}

double goalPacePercent(GoalPace pace) => switch (pace) {
  GoalPace.standard => goalStandardPercent,
  GoalPace.gentle => goalGentlePercent,
};

double bmi(double kg, double heightCm) {
  final meters = heightCm / 100;
  return kg / (meters * meters);
}

double lossCapPercent(double bmi) => switch (bmi) {
  < goalCapBmiMid => 0.5,
  < goalCapBmiHigh => 0.75,
  _ => 1,
};

GoalBlock goalBlock({
  required double startKg,
  required double percentPerWeek,
  required LocalDate start,
}) {
  final weeks = math.min(
    goalBlockWeeks,
    (goalBlockMaxLossPercent / percentPerWeek).floor(),
  );
  final weeklyKg = startKg * percentPerWeek / 100;
  final end = start.addDays(7 * weeks - 1);
  return GoalBlock(
    start: start,
    weeks: weeks,
    weeklyKg: weeklyKg,
    blockKg: weeklyKg * weeks,
    end: end,
    maintenanceEnd: end.addDays(7 * goalMaintenanceWeeks),
    anchorKg: startKg,
  );
}

LossRate lossRate(WeightRateReady rate, double trendKg) {
  double percent(double kg) => kg / trendKg * 100;
  final kg = -rate.perWeek;
  final kgLow = -rate.high;
  final kgHigh = -rate.low;
  return LossRate(
    kg: kg,
    kgLow: kgLow,
    kgHigh: kgHigh,
    percent: percent(kg),
    percentLow: percent(kgLow),
    percentHigh: percent(kgHigh),
  );
}

bool overCap(LossRate rate, double capPercent) => rate.percentLow > capPercent;

// The interval only has to touch the band to be on track, and the cap is read
// before the band so a loss that is too fast is never called slow.
PathState pathState(
  LossRate? rate, {
  required double targetPercent,
  required double capPercent,
}) {
  if (rate == null) return PathState.building;
  if (overCap(rate, capPercent)) return PathState.above;
  if (rate.percentHigh < goalBandLow * targetPercent) return PathState.below;
  if (rate.percentLow > goalBandHigh * targetPercent) return PathState.above;
  return PathState.onTrack;
}

ArrivalRange? arrivalRange({
  required double trendKg,
  required double referenceKg,
  required LossRate rate,
  required LocalDate today,
  required GoalBlock block,
}) {
  final remaining = trendKg - referenceKg;
  if (rate.kgLow <= 0) return null;
  if (remaining <= 0) return null;
  final left = ((block.end.daysSince(today) + 1) / 7)
      .clamp(0, block.weeks)
      .toDouble();
  final earliestWeeks = _weeksTo(remaining, rate.kgHigh, left, block.weeks);
  final latestWeeks = _weeksTo(remaining, rate.kgLow, left, block.weeks);
  if (earliestWeeks == null) return null;
  if (latestWeeks == null) return null;
  final earliest = today.addDays((earliestWeeks * 7).round());
  final latest = today.addDays((latestWeeks * 7).round());
  if (latest.year - earliest.year > 1) return null;
  return ArrivalRange(
    earliest: earliest,
    latest: latest,
    earliestWeeks: earliestWeeks,
    latestWeeks: latestWeeks,
  );
}

// What does not fit in the weeks left of a block waits out the maintenance
// weeks, then a new block starts. Null when the blocks allowed are not enough.
double? _weeksTo(
  double remaining,
  double perWeek,
  double left,
  int blockWeeks,
) {
  var rem = remaining;
  var weeksLeft = left;
  var waited = 0.0;
  var rounds = 0;
  while (rem / perWeek > weeksLeft && rounds < goalArrivalMaxBlocks) {
    rem -= perWeek * weeksLeft;
    waited += weeksLeft + goalMaintenanceWeeks;
    weeksLeft = blockWeeks.toDouble();
    rounds++;
  }
  if (rem / perWeek > weeksLeft) return null;
  return waited + rem / perWeek;
}

double referenceFloorKg(double heightCm) {
  final meters = heightCm / 100;
  final floorKg = bmiFloor * meters * meters;
  return (floorKg / goalReferenceStepKg).ceil() * goalReferenceStepKg;
}

WeightGoalRefusal? weightGoalRefusal({
  required int? age,
  required double? heightCm,
  required double trendKg,
  required bool pregnantOrBreastfeeding,
}) {
  if (age == null) return WeightGoalRefusal.ageMissing;
  if (age < goalMinAge) return WeightGoalRefusal.under18;
  if (heightCm == null) return WeightGoalRefusal.heightMissing;
  if (pregnantOrBreastfeeding) return WeightGoalRefusal.pregnancy;
  if (bmi(trendKg, heightCm) < bmiFloor) return WeightGoalRefusal.bmiUnderFloor;
  return null;
}

bool softMode(int yesCount) => yesCount >= goalSoftModeYes;
