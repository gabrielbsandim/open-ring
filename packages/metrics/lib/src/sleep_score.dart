import 'package:metrics/src/score.dart';
import 'package:metrics/src/scoring.dart';
import 'package:metrics/src/sleep_night.dart';

enum SleepFactor {
  duration(35),
  efficiency(20),
  latency(10),
  deep(20),
  rem(15);

  new(this.weight);

  final double weight;
}

const defaultSleepGoal = Duration(hours: 8);
const minimumScoredSleep = Duration(hours: 1);
const efficiencyZeroPercent = 65.0;
const efficiencyFullPercent = 85.0;
const latencyFullMinutes = 30.0;
const latencyZeroMinutes = 60.0;
const deepTargetPercent = 15.0;
const remTargetPercent = 20.0;

ScoreResult<SleepFactor> sleepScore(
  SleepNight? night, {
  Duration goal = defaultSleepGoal,
  bool remMeasured = true,
}) {
  if (goal <= Duration.zero) {
    throw ArgumentError.value(goal, 'goal', 'must be positive');
  }
  final latency = night?.latency;
  if (night == null || latency == null || night.asleep < minimumScoredSleep) {
    return InsufficientData([SleepFactor.duration]);
  }
  final asleepMinutes = night.asleep.inSeconds / 60;
  final efficiencyPercent = night.efficiency * 100;
  final latencyMinutes = latency.inSeconds / 60;
  final deepPercent = night.share(SleepPhase.deep)! * 100;
  final remPercent = night.share(SleepPhase.rem)! * 100;
  return weigh([
    (
      factor: SleepFactor.duration,
      baseWeight: SleepFactor.duration.weight,
      value: asleepMinutes,
      subscore: ramp(asleepMinutes, zeroAt: 0, fullAt: goal.inSeconds / 60),
    ),
    (
      factor: SleepFactor.efficiency,
      baseWeight: SleepFactor.efficiency.weight,
      value: efficiencyPercent,
      subscore: ramp(
        efficiencyPercent,
        zeroAt: efficiencyZeroPercent,
        fullAt: efficiencyFullPercent,
      ),
    ),
    (
      factor: SleepFactor.latency,
      baseWeight: SleepFactor.latency.weight,
      value: latencyMinutes,
      subscore: ramp(
        latencyMinutes,
        zeroAt: latencyZeroMinutes,
        fullAt: latencyFullMinutes,
      ),
    ),
    (
      factor: SleepFactor.deep,
      baseWeight: SleepFactor.deep.weight,
      value: deepPercent,
      subscore: ramp(deepPercent, zeroAt: 0, fullAt: deepTargetPercent),
    ),
    if (remMeasured)
      (
        factor: SleepFactor.rem,
        baseWeight: SleepFactor.rem.weight,
        value: remPercent,
        subscore: ramp(remPercent, zeroAt: 0, fullAt: remTargetPercent),
      ),
  ]);
}
