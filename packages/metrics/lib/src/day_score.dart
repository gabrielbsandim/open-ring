import 'dart:math' as math;

import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/local_date.dart';
import 'package:metrics/src/readiness.dart';
import 'package:metrics/src/score.dart';
import 'package:metrics/src/scoring.dart';

enum DayScorePillar { sleep, movement, recovery, stress, oxygen }

enum DayScoreFactor {
  sleep(30, DayScorePillar.sleep),
  steps(15, DayScorePillar.movement),
  intensity(20, DayScorePillar.movement),
  hrv(10, DayScorePillar.recovery),
  restingHeartRate(10, DayScorePillar.recovery),
  stress(10, DayScorePillar.stress),
  spo2(5, DayScorePillar.oxygen);

  new(this.weight, this.pillar);

  final double weight;
  final DayScorePillar pillar;
}

const dayScoreMinCoverage = 60.0;
const dayScoreFullCoverage = 100.0;
const dayScoreGreatFrom = 85;
const dayScoreGoodFrom = 70;
const dayScoreMixedFrom = 55;
const intensityWeeklyTarget = 150.0;

// On a day whose readiness is below fair, steps are scored against this
// share of the goal.
const lowReadinessStepGoalFactor = 0.6;
const stressZeroZ = 3.0;
const stressFullZ = -1.0;
const stressMinSpread = 3.0;
const spo2ZeroAt = 90.0;
const spo2FullAt = 95.0;

enum DayScoreBand { low, mixed, good, great }

DayScoreBand dayScoreBand(int score) => switch (score) {
  >= dayScoreGreatFrom => DayScoreBand.great,
  >= dayScoreGoodFrom => DayScoreBand.good,
  >= dayScoreMixedFrom => DayScoreBand.mixed,
  _ => DayScoreBand.low,
};

extension DayScoreCoverage on Scored<DayScoreFactor> {
  double get coverage =>
      contributions.fold(0, (sum, c) => sum + c.factor.weight);

  bool get isFull => coverage >= dayScoreFullCoverage;

  List<DayScoreFactor> get missing => [
    for (final factor in DayScoreFactor.values)
      if (of(factor) == null) factor,
  ];
}

BaselineResult stressBaseline(
  Iterable<DailyValue> dailyStressMean, {
  required LocalDate today,
}) =>
    personalBaseline(dailyStressMean, today: today, minSpread: stressMinSpread);

Part<DayScoreFactor> _part(
  DayScoreFactor factor,
  double value,
  double subscore,
) => (
  factor: factor,
  baseWeight: factor.weight,
  value: value,
  subscore: subscore,
);

final class DayScoreInputs {
  const new({
    required this.sleepScore,
    required this.steps,
    required this.stepGoal,
    this.intensityMinutes,
    this.hrv,
    this.restingHeartRate,
    this.stress,
    this.spo2Mean,
    this.readiness,
  });

  final int? sleepScore;
  final int? steps;
  final int stepGoal;
  final double? intensityMinutes;
  final BaselineDeviation? hrv;
  final BaselineDeviation? restingHeartRate;
  final BaselineDeviation? stress;
  final double? spo2Mean;

  /// The day's readiness score, when it had one.
  final int? readiness;

  bool get lowReadiness {
    final readiness = this.readiness;
    return readiness != null && readiness < readinessFairFrom;
  }

  /// The step goal the score uses: a low readiness day asks for less.
  int get dayStepGoal {
    if (!lowReadiness) return stepGoal;
    return math.max(1, (stepGoal * lowReadinessStepGoalFactor).round());
  }

  /// The points the steps would have earned against the full goal, before
  /// any rescale. Null on a day that is not low or has no steps.
  double? get fullGoalStepPoints {
    final walked = this.walked;
    if (!lowReadiness || walked == null) return null;
    return DayScoreFactor.steps.weight *
        ramp(walked, zeroAt: 0, fullAt: stepGoal.toDouble());
  }

  // Zero steps means the ring was off the finger, so it counts as missing.
  double? get walked {
    final steps = this.steps;
    if (steps == null || steps <= 0) return null;
    return steps.toDouble();
  }

  List<Part<DayScoreFactor>> get _parts {
    if (stepGoal < 1) {
      throw ArgumentError.value(stepGoal, 'stepGoal', 'must be at least 1');
    }
    final sleepScore = this.sleepScore;
    final walked = this.walked;
    final intensityMinutes = this.intensityMinutes;
    final hrv = this.hrv;
    final restingHeartRate = this.restingHeartRate;
    final stress = this.stress;
    final spo2Mean = this.spo2Mean;
    return [
      if (sleepScore != null)
        _part(
          DayScoreFactor.sleep,
          sleepScore.toDouble(),
          ramp(sleepScore.toDouble(), zeroAt: 0, fullAt: 100),
        ),
      if (walked != null)
        _part(
          DayScoreFactor.steps,
          walked,
          ramp(walked, zeroAt: 0, fullAt: dayStepGoal.toDouble()),
        ),
      if (intensityMinutes != null)
        _part(
          DayScoreFactor.intensity,
          intensityMinutes,
          ramp(intensityMinutes, zeroAt: 0, fullAt: intensityWeeklyTarget),
        ),
      if (hrv != null)
        _part(
          DayScoreFactor.hrv,
          hrv.zScore,
          ramp(hrv.zScore, zeroAt: hrvZeroZ, fullAt: hrvFullZ),
        ),
      if (restingHeartRate != null)
        _part(
          DayScoreFactor.restingHeartRate,
          restingHeartRate.zScore,
          ramp(
            restingHeartRate.zScore,
            zeroAt: restingHeartRateZeroZ,
            fullAt: restingHeartRateFullZ,
          ),
        ),
      if (stress != null)
        _part(
          DayScoreFactor.stress,
          stress.zScore,
          ramp(stress.zScore, zeroAt: stressZeroZ, fullAt: stressFullZ),
        ),
      if (spo2Mean != null)
        _part(
          DayScoreFactor.spo2,
          spo2Mean,
          ramp(spo2Mean, zeroAt: spo2ZeroAt, fullAt: spo2FullAt),
        ),
    ];
  }

  // What each present factor earned on the published scale, score or not.
  List<Contribution<DayScoreFactor>> get contributions => [
    for (final part in _parts)
      Contribution(
        factor: part.factor,
        value: part.value,
        subscore: part.subscore,
        weight: part.baseWeight,
      ),
  ];

  ScoreResult<DayScoreFactor> get score {
    final parts = _parts;
    final present = {for (final part in parts) part.factor};
    final coverage = parts.fold<double>(0, (sum, p) => sum + p.baseWeight);
    final scorable =
        present.contains(DayScoreFactor.sleep) &&
        present.contains(DayScoreFactor.steps) &&
        coverage >= dayScoreMinCoverage;
    if (scorable) return weigh(parts);
    return InsufficientData([
      for (final factor in DayScoreFactor.values)
        if (!present.contains(factor)) factor,
    ]);
  }
}

ScoreResult<DayScoreFactor> dayScore({
  required int? sleepScore,
  required int? steps,
  required int stepGoal,
  double? intensityMinutes,
  BaselineDeviation? hrv,
  BaselineDeviation? restingHeartRate,
  BaselineDeviation? stress,
  double? spo2Mean,
  int? readiness,
}) => DayScoreInputs(
  sleepScore: sleepScore,
  steps: steps,
  stepGoal: stepGoal,
  intensityMinutes: intensityMinutes,
  hrv: hrv,
  restingHeartRate: restingHeartRate,
  stress: stress,
  spo2Mean: spo2Mean,
  readiness: readiness,
).score;
