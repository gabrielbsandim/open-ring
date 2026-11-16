import 'package:metrics/src/score.dart';
import 'package:metrics/src/scoring.dart';

enum OverallGroup { heart, sleep, movement, body }

enum OverallFactor {
  fitness(30, OverallGroup.heart),
  restingHeartRate(15, OverallGroup.heart),
  sleepDuration(10, OverallGroup.sleep),
  sleepRegularity(15, OverallGroup.sleep),
  movement(20, OverallGroup.movement),
  body(10, OverallGroup.body);

  new(this.weight, this.group);

  final double weight;
  final OverallGroup group;
}

const overallMinCoverage = 50.0;
const overallFullCoverage = 100.0;
const overallStrongFrom = 85;
const overallSolidFrom = 70;
const overallBuildingFrom = 55;
const overallNoiseBelow = 2;

const fitnessFullPercentile = 90.0;
const overallRestingZeroAt = 80.0;
const overallRestingFullAt = 50.0;
const sleepHoursZeroAt = 5.0;
const sleepHoursFullAt = 7.0;
const sleepRegularityZeroAt = 50.0;
const sleepRegularityFullAt = 90.0;

const movementMinutesWeight = 10.0;
const movementStrengthWeight = 4.0;
const movementStepsWeight = 6.0;
const movementMinutesTarget = 150.0;
const movementMinutesCeiling = 300.0;
const movementTargetShare = 0.75;
const movementStrengthTarget = 2.0;
const movementStepsZeroAt = 2500.0;
const movementStepsFullAt = 8000.0;
const movementStepsFullAtOlder = 7000.0;

const waistToHeightFullAt = 0.50;
const waistToHeightZeroAt = 0.65;
const waistToHeightFloor = 0.40;
const bmiFloor = 18.5;
const bmiFullAt = 25.0;
const bmiZeroAt = 35.0;
const bodyWeightWithoutWaist = 5.0;

enum OverallBand { start, building, solid, strong }

OverallBand overallBand(int score) => switch (score) {
  >= overallStrongFrom => OverallBand.strong,
  >= overallSolidFrom => OverallBand.solid,
  >= overallBuildingFrom => OverallBand.building,
  _ => OverallBand.start,
};

extension OverallCoverage on Scored<OverallFactor> {
  List<OverallFactor> get missing => [
    for (final factor in OverallFactor.values)
      if (of(factor) == null) factor,
  ];
}

typedef MovementPoints = ({double minutes, double strength, double steps});

final class OverallInputs {
  const new({
    this.fitnessPercentile,
    this.restingHeartRate,
    this.sleepHours,
    this.sleepRegularity,
    this.weeklyMinutes,
    this.strengthPerWeek = 0,
    this.dailySteps,
    this.olderAdult = false,
    this.waistToHeight,
    this.bmi,
  });

  final double? fitnessPercentile;
  final double? restingHeartRate;
  final double? sleepHours;
  final double? sleepRegularity;
  final double? weeklyMinutes;
  final double strengthPerWeek;
  final double? dailySteps;
  final bool olderAdult;
  final double? waistToHeight;
  final double? bmi;

  // Points of the three movement habits, out of 10, 4 and 6.
  MovementPoints? get movementPoints {
    final minutes = weeklyMinutes;
    final steps = dailySteps;
    if (minutes == null || steps == null) return null;
    final toTarget = ramp(minutes, zeroAt: 0, fullAt: movementMinutesTarget);
    final beyond = ramp(
      minutes,
      zeroAt: movementMinutesTarget,
      fullAt: movementMinutesCeiling,
    );
    return (
      minutes:
          movementMinutesWeight *
          (movementTargetShare * toTarget + (1 - movementTargetShare) * beyond),
      strength:
          movementStrengthWeight *
          ramp(strengthPerWeek, zeroAt: 0, fullAt: movementStrengthTarget),
      steps:
          movementStepsWeight *
          ramp(
            steps,
            zeroAt: movementStepsZeroAt,
            fullAt: olderAdult ? movementStepsFullAtOlder : movementStepsFullAt,
          ),
    );
  }

  // A value under the healthy range removes the factor: it is never scored.
  Part<OverallFactor>? get _body {
    final waistToHeight = this.waistToHeight;
    if (waistToHeight != null) return _waistPart(waistToHeight);
    final bmi = this.bmi;
    if (bmi == null || bmi < bmiFloor) return null;
    return (
      factor: OverallFactor.body,
      baseWeight: bodyWeightWithoutWaist,
      value: bmi,
      subscore: ramp(bmi, zeroAt: bmiZeroAt, fullAt: bmiFullAt),
    );
  }

  Part<OverallFactor>? _waistPart(double waistToHeight) {
    if (waistToHeight < waistToHeightFloor) return null;
    return _part(
      OverallFactor.body,
      waistToHeight,
      ramp(
        waistToHeight,
        zeroAt: waistToHeightZeroAt,
        fullAt: waistToHeightFullAt,
      ),
    );
  }

  List<Part<OverallFactor>> get _parts {
    final fitnessPercentile = this.fitnessPercentile;
    final restingHeartRate = this.restingHeartRate;
    final sleepHours = this.sleepHours;
    final sleepRegularity = this.sleepRegularity;
    final movement = movementPoints;
    return [
      if (fitnessPercentile != null)
        _part(
          OverallFactor.fitness,
          fitnessPercentile,
          ramp(fitnessPercentile, zeroAt: 0, fullAt: fitnessFullPercentile),
        ),
      if (restingHeartRate != null)
        _part(
          OverallFactor.restingHeartRate,
          restingHeartRate,
          ramp(
            restingHeartRate,
            zeroAt: overallRestingZeroAt,
            fullAt: overallRestingFullAt,
          ),
        ),
      if (sleepHours != null)
        _part(
          OverallFactor.sleepDuration,
          sleepHours,
          ramp(sleepHours, zeroAt: sleepHoursZeroAt, fullAt: sleepHoursFullAt),
        ),
      if (sleepRegularity != null)
        _part(
          OverallFactor.sleepRegularity,
          sleepRegularity,
          ramp(
            sleepRegularity,
            zeroAt: sleepRegularityZeroAt,
            fullAt: sleepRegularityFullAt,
          ),
        ),
      if (movement != null)
        _part(
          OverallFactor.movement,
          weeklyMinutes ?? 0,
          (movement.minutes + movement.strength + movement.steps) /
              OverallFactor.movement.weight,
        ),
      ?_body,
    ];
  }

  // What each present factor earned on the published scale, score or not.
  List<Contribution<OverallFactor>> get contributions => [
    for (final part in _parts)
      Contribution(
        factor: part.factor,
        value: part.value,
        subscore: part.subscore,
        weight: part.baseWeight,
      ),
  ];

  double get coverage =>
      _parts.fold<double>(0, (sum, part) => sum + part.baseWeight);

  bool get isFull => coverage >= overallFullCoverage;

  ScoreResult<OverallFactor> get score {
    final parts = _parts;
    final present = {for (final part in parts) part.factor};
    final heart =
        present.contains(OverallFactor.fitness) ||
        present.contains(OverallFactor.restingHeartRate);
    final sleep =
        present.contains(OverallFactor.sleepDuration) ||
        present.contains(OverallFactor.sleepRegularity);
    if (heart && sleep && coverage >= overallMinCoverage) return weigh(parts);
    return InsufficientData([
      for (final factor in OverallFactor.values)
        if (!present.contains(factor)) factor,
    ]);
  }
}

Part<OverallFactor> _part(
  OverallFactor factor,
  double value,
  double subscore,
) => (
  factor: factor,
  baseWeight: factor.weight,
  value: value,
  subscore: subscore,
);
