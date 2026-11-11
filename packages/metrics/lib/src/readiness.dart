import 'package:metrics/src/activity_load.dart';
import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/score.dart';
import 'package:metrics/src/scoring.dart';

enum ReadinessFactor {
  sleep(35),
  hrv(30),
  restingHeartRate(20),
  activityLoad(15);

  new(this.weight);

  final double weight;
}

const hrvZeroZ = -3.0;
const hrvFullZ = 1.0;
const restingHeartRateZeroZ = 3.0;
const restingHeartRateFullZ = -1.0;
const loadFullRatio = 1.3;
const loadZeroRatio = 2.0;
const readinessOptimalFrom = 85;
const readinessGoodFrom = 70;
const readinessFairFrom = 55;

enum ReadinessBand { low, fair, good, optimal }

ReadinessBand readinessBand(int score) => switch (score) {
  >= readinessOptimalFrom => ReadinessBand.optimal,
  >= readinessGoodFrom => ReadinessBand.good,
  >= readinessFairFrom => ReadinessBand.fair,
  _ => ReadinessBand.low,
};

ScoreResult<ReadinessFactor> readiness({
  required int? sleepScore,
  required BaselineDeviation? hrv,
  required BaselineDeviation? restingHeartRate,
  ActivityLoad? activityLoad,
}) {
  final missing = [
    if (sleepScore == null) ReadinessFactor.sleep,
    if (hrv == null) ReadinessFactor.hrv,
    if (restingHeartRate == null) ReadinessFactor.restingHeartRate,
  ];
  if (sleepScore == null || hrv == null || restingHeartRate == null) {
    return InsufficientData(missing);
  }
  final sleep = sleepScore.toDouble();
  return weigh([
    (
      factor: ReadinessFactor.sleep,
      baseWeight: ReadinessFactor.sleep.weight,
      value: sleep,
      subscore: ramp(sleep, zeroAt: 0, fullAt: 100),
    ),
    (
      factor: ReadinessFactor.hrv,
      baseWeight: ReadinessFactor.hrv.weight,
      value: hrv.zScore,
      subscore: ramp(hrv.zScore, zeroAt: hrvZeroZ, fullAt: hrvFullZ),
    ),
    (
      factor: ReadinessFactor.restingHeartRate,
      baseWeight: ReadinessFactor.restingHeartRate.weight,
      value: restingHeartRate.zScore,
      subscore: ramp(
        restingHeartRate.zScore,
        zeroAt: restingHeartRateZeroZ,
        fullAt: restingHeartRateFullZ,
      ),
    ),
    if (activityLoad != null)
      (
        factor: ReadinessFactor.activityLoad,
        baseWeight: ReadinessFactor.activityLoad.weight,
        value: activityLoad.ratio,
        subscore: ramp(
          activityLoad.ratio,
          zeroAt: loadZeroRatio,
          fullAt: loadFullRatio,
        ),
      ),
  ]);
}
