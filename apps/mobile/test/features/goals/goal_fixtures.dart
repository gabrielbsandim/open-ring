import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';

void expectSameGoal(Goal? actual, Goal expected) {
  expect(actual, isNotNull);
  final goal = actual!;
  expect(goal.id, expected.id);
  expect(goal.kind, expected.kind);
  expect(goal.pace, expected.pace);
  expect(goal.startedOn, expected.startedOn);
  expect(goal.anchorKg, expected.anchorKg);
  expect(goal.referenceKg, expected.referenceKg);
  expect(goal.blockStartedOn, expected.blockStartedOn);
  expect(goal.blockAnchorKg, expected.blockAnchorKg);
  expect(goal.phase, expected.phase);
  expect(goal.phaseSince, expected.phaseSince);
  expect(goal.phaseUntil, expected.phaseUntil);
  expectSameLevers(goal.levers, expected.levers);
  expect(goal.endedOn, expected.endedOn);
  expect(goal.endReason, expected.endReason);
}

void expectSameLevers(List<Lever> actual, List<Lever> expected) {
  expect(
    [for (final lever in actual) (lever.kind, lever.target)],
    [for (final lever in expected) (lever.kind, lever.target)],
  );
}

void expectSameChange(LeverChange? actual, LeverChange? expected) {
  expect(actual == null, expected == null);
  if (actual == null || expected == null) return;
  expect(actual.kind, expected.kind);
  expect(actual.from, expected.from);
  expect(actual.to, expected.to);
}

void expectSameInputs(ReviewInputs actual, ReviewInputs expected) {
  expect(actual.kind, expected.kind);
  expect(actual.week, expected.week);
  expect(actual.levers.length, expected.levers.length);
  for (var i = 0; i < expected.levers.length; i++) {
    expect(actual.levers[i].lever.kind, expected.levers[i].lever.kind);
    expect(actual.levers[i].lever.target, expected.levers[i].lever.target);
    expect(actual.levers[i].achieved, expected.levers[i].achieved);
  }
  expect(actual.adherencePrevious, expected.adherencePrevious);
  expect(actual.baseline.stepsMedian14, expected.baseline.stepsMedian14);
  expect(actual.baseline.bedMedian, expected.baseline.bedMedian);
  expect(actual.baseline.wakeMedian, expected.baseline.wakeMedian);
  expect(actual.baseline.effortMean4Weeks, expected.baseline.effortMean4Weeks);
  expect(
    actual.baseline.strengthDaysUsual,
    expected.baseline.strengthDaysUsual,
  );
  expect(actual.effortRaisesInRow, expected.effortRaisesInRow);
  expect(actual.rate == null, expected.rate == null);
  expect(actual.rate?.kg, expected.rate?.kg);
  expect(actual.rate?.kgLow, expected.rate?.kgLow);
  expect(actual.rate?.kgHigh, expected.rate?.kgHigh);
  expect(actual.rate?.percent, expected.rate?.percent);
  expect(actual.rate?.percentLow, expected.rate?.percentLow);
  expect(actual.rate?.percentHigh, expected.rate?.percentHigh);
  expect(actual.targetPercent, expected.targetPercent);
  expect(actual.capPercent, expected.capPercent);
  expect(actual.previousPercentLow, expected.previousPercentLow);
  expect(actual.bmi, expected.bmi);
  expect(actual.pregnantOrBreastfeeding, expected.pregnantOrBreastfeeding);
  expect(actual.screeningPositive, expected.screeningPositive);
  expect(actual.bodyOn, expected.bodyOn);
  expect(actual.readiness, expected.readiness);
  expect(actual.recoveryPrevious, expected.recoveryPrevious);
  expect(actual.energy, expected.energy);
  expect(actual.energyPrevious, expected.energyPrevious);
  expect(actual.foodOrWeight, expected.foodOrWeight);
  expect(actual.foodOrWeightPrevious, expected.foodOrWeightPrevious);
}

const strengthLever = Lever(kind: LeverKind.strengthDays, target: 2);
const sleepLever = Lever(kind: LeverKind.sleepWindow, target: 690);
const stepsLever = Lever(kind: LeverKind.steps, target: 9000);

const f1 = ReviewInputs(
  kind: GoalKind.loseFat,
  week: 3,
  levers: [
    LeverWeek(lever: strengthLever, achieved: 2),
    LeverWeek(lever: sleepLever, achieved: 6),
    LeverWeek(lever: stepsLever, achieved: 5),
  ],
  adherencePrevious: 1,
  baseline: LeverBaseline(
    stepsMedian14: 8000,
    bedMedian: 705,
    wakeMedian: 405,
    effortMean4Weeks: null,
    strengthDaysUsual: 1,
  ),
  effortRaisesInRow: 0,
  rate: LossRate(
    kg: 0.2958,
    kgLow: 0.2034,
    kgHigh: 0.3881,
    percent: 0.380,
    percentLow: 0.261,
    percentHigh: 0.499,
  ),
  targetPercent: 0.5,
  capPercent: 0.5,
  previousPercentLow: 0.3,
  bmi: 24.55,
  pregnantOrBreastfeeding: false,
  screeningPositive: false,
  bodyOn: true,
  readiness: [76, 72, 70, 68, 74, 71, 76],
  recoveryPrevious: false,
  energy: CheckInEnergy.good,
  energyPrevious: CheckInEnergy.normal,
  foodOrWeight: false,
  foodOrWeightPrevious: false,
);

const f0 = ReviewInputs(
  kind: GoalKind.sleepBetter,
  week: 1,
  levers: [],
  adherencePrevious: null,
  baseline: LeverBaseline(
    stepsMedian14: null,
    bedMedian: null,
    wakeMedian: null,
    effortMean4Weeks: null,
    strengthDaysUsual: 0,
  ),
  effortRaisesInRow: 0,
  rate: null,
  targetPercent: 0.5,
  capPercent: 0.5,
  previousPercentLow: null,
  bmi: null,
  pregnantOrBreastfeeding: false,
  screeningPositive: false,
  bodyOn: false,
  readiness: [null, null, null, null, null, null, null],
  recoveryPrevious: false,
  energy: null,
  energyPrevious: null,
  foodOrWeight: null,
  foodOrWeightPrevious: null,
);

ReviewInputs f1With({
  required CheckInEnergy? energy,
  required CheckInEnergy? energyPrevious,
  required bool? foodOrWeight,
}) => ReviewInputs(
  kind: f1.kind,
  week: f1.week,
  levers: f1.levers,
  adherencePrevious: f1.adherencePrevious,
  baseline: f1.baseline,
  effortRaisesInRow: f1.effortRaisesInRow,
  rate: f1.rate,
  targetPercent: f1.targetPercent,
  capPercent: f1.capPercent,
  previousPercentLow: f1.previousPercentLow,
  bmi: f1.bmi,
  pregnantOrBreastfeeding: f1.pregnantOrBreastfeeding,
  screeningPositive: f1.screeningPositive,
  bodyOn: f1.bodyOn,
  readiness: f1.readiness,
  recoveryPrevious: f1.recoveryPrevious,
  energy: energy,
  energyPrevious: energyPrevious,
  foodOrWeight: foodOrWeight,
  foodOrWeightPrevious: f1.foodOrWeightPrevious,
);

ReviewInputs f1WithBmi(double bmi) => ReviewInputs(
  kind: f1.kind,
  week: f1.week,
  levers: f1.levers,
  adherencePrevious: f1.adherencePrevious,
  baseline: f1.baseline,
  effortRaisesInRow: f1.effortRaisesInRow,
  rate: f1.rate,
  targetPercent: f1.targetPercent,
  capPercent: f1.capPercent,
  previousPercentLow: f1.previousPercentLow,
  bmi: bmi,
  pregnantOrBreastfeeding: f1.pregnantOrBreastfeeding,
  screeningPositive: f1.screeningPositive,
  bodyOn: f1.bodyOn,
  readiness: f1.readiness,
  recoveryPrevious: f1.recoveryPrevious,
  energy: f1.energy,
  energyPrevious: f1.energyPrevious,
  foodOrWeight: f1.foodOrWeight,
  foodOrWeightPrevious: f1.foodOrWeightPrevious,
);

// Four of the seven values are under the fair band, which is rule 4.
ReviewInputs f1Recovering({
  required bool recoveryPrevious,
  CheckInEnergy? energy = CheckInEnergy.good,
  CheckInEnergy? energyPrevious = CheckInEnergy.normal,
  bool? foodOrWeight = false,
}) => ReviewInputs(
  kind: f1.kind,
  week: f1.week,
  levers: f1.levers,
  adherencePrevious: f1.adherencePrevious,
  baseline: f1.baseline,
  effortRaisesInRow: f1.effortRaisesInRow,
  rate: f1.rate,
  targetPercent: f1.targetPercent,
  capPercent: f1.capPercent,
  previousPercentLow: f1.previousPercentLow,
  bmi: f1.bmi,
  pregnantOrBreastfeeding: f1.pregnantOrBreastfeeding,
  screeningPositive: f1.screeningPositive,
  bodyOn: f1.bodyOn,
  readiness: [52, 49, 58, 54, 61, 50, 66],
  recoveryPrevious: recoveryPrevious,
  energy: energy,
  energyPrevious: energyPrevious,
  foodOrWeight: foodOrWeight,
  foodOrWeightPrevious: f1.foodOrWeightPrevious,
);
