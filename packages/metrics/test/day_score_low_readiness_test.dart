import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

BaselineDeviation z(double zScore) =>
    BaselineDeviation(today: 1, baseline: 1, zScore: zScore);

Scored<DayScoreFactor> scored(ScoreResult<DayScoreFactor> result) =>
    result as Scored<DayScoreFactor>;

ScoreResult<DayScoreFactor> scoreOf({int? readiness}) => dayScore(
  sleepScore: 80,
  steps: 4800,
  stepGoal: 8000,
  intensityMinutes: 150,
  hrv: z(1),
  restingHeartRate: z(-1),
  stress: z(-1),
  spo2Mean: 96,
  readiness: readiness,
);

DayScoreInputs inputsOf({
  int? readiness,
  int? steps = 4000,
  int stepGoal = 8000,
}) => DayScoreInputs(
  sleepScore: 80,
  steps: steps,
  stepGoal: stepGoal,
  intensityMinutes: 150,
  readiness: readiness,
);

double stepsSubscore(int? readiness) =>
    scored(scoreOf(readiness: readiness)).of(DayScoreFactor.steps)!.subscore;

void main() {
  test('the low readiness factor is 0.6', () {
    expect(lowReadinessStepGoalFactor, 0.6);
  });

  group('the steps subscore against the readiness', () {
    test('readiness 54 scores 4800 steps against 60 percent of the goal', () {
      expect(stepsSubscore(54), closeTo(1.0, 1e-9));
    });

    test('readiness 55 is not low and scores against the full goal', () {
      expect(stepsSubscore(55), closeTo(0.6, 1e-9));
    });

    test('a null readiness scores against the full goal', () {
      expect(stepsSubscore(null), closeTo(0.6, 1e-9));
    });

    test('the steps factor earns its full weight on a low day', () {
      final steps = scored(scoreOf(readiness: 54)).of(DayScoreFactor.steps)!;

      expect(steps.points, closeTo(DayScoreFactor.steps.weight, 1e-9));
    });

    test('a high readiness leaves the day scored as before', () {
      expect(
        scored(scoreOf(readiness: 80)).total,
        closeTo(scored(scoreOf()).total, 1e-9),
      );
    });
  });

  group('the other factors ignore the readiness', () {
    test('every factor but steps is the same at 40 and at 80', () {
      final low = scored(scoreOf(readiness: 40));
      final high = scored(scoreOf(readiness: 80));
      final others = DayScoreFactor.values.where(
        (f) => f != DayScoreFactor.steps,
      );

      for (final factor in others) {
        expect(
          low.of(factor)!.subscore,
          closeTo(high.of(factor)!.subscore, 1e-9),
          reason: factor.name,
        );
      }
    });
  });

  group('dayStepGoal', () {
    test('is 4800 for a goal of 8000 and readiness 40', () {
      expect(inputsOf(readiness: 40).dayStepGoal, 4800);
    });

    test('equals the goal at readiness 55, 80 and null', () {
      expect(inputsOf(readiness: 55).dayStepGoal, 8000);
      expect(inputsOf(readiness: 80).dayStepGoal, 8000);
      expect(inputsOf().dayStepGoal, 8000);
    });

    test('is 1 for a goal of 1 at readiness 40', () {
      expect(inputsOf(readiness: 40, stepGoal: 1).dayStepGoal, 1);
    });

    test('is 1 for a goal of 2 at readiness 40', () {
      expect(inputsOf(readiness: 40, stepGoal: 2).dayStepGoal, 1);
    });

    test('rounds 0.6 of 7499 to 4499', () {
      expect(inputsOf(readiness: 40, stepGoal: 7499).dayStepGoal, 4499);
    });
  });

  group('lowReadiness', () {
    test('is true at 54 and false at 55 and null', () {
      expect(inputsOf(readiness: 54).lowReadiness, isTrue);
      expect(inputsOf(readiness: 55).lowReadiness, isFalse);
      expect(inputsOf().lowReadiness, isFalse);
    });
  });

  group('fullGoalStepPoints', () {
    test('is 7.5 for 4000 steps against 8000 at readiness 40', () {
      expect(inputsOf(readiness: 40).fullGoalStepPoints, closeTo(7.5, 1e-9));
    });

    test('is null when the day is not low', () {
      expect(inputsOf(readiness: 80).fullGoalStepPoints, isNull);
      expect(inputsOf().fullGoalStepPoints, isNull);
    });

    test('is null on a low day without steps', () {
      expect(inputsOf(readiness: 40, steps: null).fullGoalStepPoints, isNull);
      expect(inputsOf(readiness: 40, steps: 0).fullGoalStepPoints, isNull);
    });
  });
}
