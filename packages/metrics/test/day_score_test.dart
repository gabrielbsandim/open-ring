import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

BaselineDeviation z(double zScore) =>
    BaselineDeviation(today: 1, baseline: 1, zScore: zScore);

Scored<DayScoreFactor> scored(ScoreResult<DayScoreFactor> result) =>
    result as Scored<DayScoreFactor>;

ScoreResult<DayScoreFactor> full({
  int? sleepScore = 80,
  int? steps = 8000,
  double? intensityMinutes = 150,
  double? hrvZ = 1,
  double? restingZ = -1,
  double? stressZ = -1,
  double? spo2Mean = 96,
}) => dayScore(
  sleepScore: sleepScore,
  steps: steps,
  stepGoal: 8000,
  intensityMinutes: intensityMinutes,
  hrv: hrvZ == null ? null : z(hrvZ),
  restingHeartRate: restingZ == null ? null : z(restingZ),
  stress: stressZ == null ? null : z(stressZ),
  spo2Mean: spo2Mean,
);

void main() {
  test('the weights add up to 100 points', () {
    final total = DayScoreFactor.values.fold<double>(0, (s, f) => s + f.weight);

    expect(total, 100);
  });

  test('each band starts at its published score', () {
    expect(dayScoreBand(100), DayScoreBand.great);
    expect(dayScoreBand(85), DayScoreBand.great);
    expect(dayScoreBand(84), DayScoreBand.good);
    expect(dayScoreBand(70), DayScoreBand.good);
    expect(dayScoreBand(69), DayScoreBand.mixed);
    expect(dayScoreBand(55), DayScoreBand.mixed);
    expect(dayScoreBand(54), DayScoreBand.low);
    expect(dayScoreBand(0), DayScoreBand.low);
  });

  test('every factor at its best with a sleep score of 80 gives 94', () {
    final result = scored(full());

    expect(result.of(DayScoreFactor.sleep)!.points, closeTo(24, 1e-9));
    expect(result.total, closeTo(94, 1e-9));
    expect(result.value, 94);
    expect(result.coverage, 100);
    expect(result.isFull, isTrue);
    expect(result.missing, isEmpty);
  });

  test('the worked example of an ordinary day', () {
    final result = scored(
      dayScore(
        sleepScore: 76,
        steps: 8560,
        stepGoal: 8000,
        intensityMinutes: 117,
        hrv: z(0.9),
        restingHeartRate: z(2.2),
        stress: z(0.1),
        spo2Mean: 96,
      ),
    );

    expect(result.of(DayScoreFactor.sleep)!.points, closeTo(22.8, 1e-9));
    expect(result.of(DayScoreFactor.steps)!.points, closeTo(15, 1e-9));
    expect(result.of(DayScoreFactor.intensity)!.points, closeTo(15.6, 1e-9));
    expect(result.of(DayScoreFactor.hrv)!.points, closeTo(9.75, 1e-9));
    expect(
      result.of(DayScoreFactor.restingHeartRate)!.points,
      closeTo(2, 1e-9),
    );
    expect(result.of(DayScoreFactor.stress)!.points, closeTo(7.25, 1e-9));
    expect(result.of(DayScoreFactor.spo2)!.points, closeTo(5, 1e-9));
    expect(result.value, 77);
  });

  test('steps above the goal earn nothing extra', () {
    final atGoal = scored(full());
    final above = scored(full(steps: 20000));

    expect(above.of(DayScoreFactor.steps)!.subscore, 1);
    expect(above.value, atGoal.value);
  });

  test('the stress and oxygen ramps end where they are published', () {
    final worst = scored(full(stressZ: 3, spo2Mean: 90));
    final middle = scored(full(stressZ: 1, spo2Mean: 92.5));

    expect(worst.of(DayScoreFactor.stress)!.subscore, 0);
    expect(worst.of(DayScoreFactor.spo2)!.subscore, 0);
    expect(middle.of(DayScoreFactor.stress)!.subscore, 0.5);
    expect(middle.of(DayScoreFactor.spo2)!.subscore, 0.5);
  });

  group('coverage', () {
    test('a missing factor rescales the rest instead of costing points', () {
      final result = scored(full(stressZ: null, spo2Mean: null));

      expect(result.coverage, 85);
      expect(result.isFull, isFalse);
      expect(result.missing, [DayScoreFactor.stress, DayScoreFactor.spo2]);
      expect(result.of(DayScoreFactor.sleep)!.weight, closeTo(30 / 0.85, 1e-9));
      expect(result.total, closeTo(100 * 79 / 85, 1e-9));
      expect(result.value, 93);
    });

    test('sleep, steps and stress alone are under the minimum', () {
      final result = full(
        intensityMinutes: null,
        hrvZ: null,
        restingZ: null,
        spo2Mean: null,
      );

      expect(result, isA<InsufficientData<DayScoreFactor>>());
      expect((result as InsufficientData<DayScoreFactor>).missing, [
        DayScoreFactor.intensity,
        DayScoreFactor.hrv,
        DayScoreFactor.restingHeartRate,
        DayScoreFactor.spo2,
      ]);
    });

    test('sleep, steps, stress and oxygen reach the minimum of 60', () {
      final result = scored(
        full(intensityMinutes: null, hrvZ: null, restingZ: null),
      );

      expect(result.coverage, 60);
    });

    test('without the night there is no score, whatever else is there', () {
      final result = full(sleepScore: null);

      expect(result, isA<InsufficientData<DayScoreFactor>>());
      expect((result as InsufficientData<DayScoreFactor>).missing, [
        DayScoreFactor.sleep,
      ]);
    });

    test('zero steps reads as the ring off the finger', () {
      final none = full(steps: 0);
      final absent = full(steps: null);

      expect((none as InsufficientData<DayScoreFactor>).missing, [
        DayScoreFactor.steps,
      ]);
      expect(absent, isA<InsufficientData<DayScoreFactor>>());
    });
  });

  test('a step goal below one is refused', () {
    expect(
      () => dayScore(sleepScore: 80, steps: 100, stepGoal: 0),
      throwsArgumentError,
    );
  });

  group('inputs', () {
    const inputs = DayScoreInputs(
      sleepScore: 80,
      steps: 4000,
      stepGoal: 8000,
      intensityMinutes: 75,
      spo2Mean: 92.5,
    );

    test('contributions keep the published weights when rescaled', () {
      final points = {
        for (final part in inputs.contributions) part.factor: part.points,
      };

      expect(points, {
        DayScoreFactor.sleep: 24.0,
        DayScoreFactor.steps: 7.5,
        DayScoreFactor.intensity: 10.0,
        DayScoreFactor.spo2: 2.5,
      });
    });

    test('contributions exist for a day that has no score', () {
      const thin = DayScoreInputs(sleepScore: null, steps: 0, stepGoal: 8000);

      expect(thin.score, isA<InsufficientData<DayScoreFactor>>());
      expect(thin.contributions, isEmpty);
      expect(thin.walked, isNull);
    });

    test('scores the same as the function', () {
      final scored = inputs.score as Scored<DayScoreFactor>;
      final direct = dayScore(
        sleepScore: 80,
        steps: 4000,
        stepGoal: 8000,
        intensityMinutes: 75,
        spo2Mean: 92.5,
      ) as Scored<DayScoreFactor>;

      expect(scored.value, direct.value);
      expect(scored.value, 63);
    });

    test('the rules the app prints match the ramps', () {
      expect([hrvZeroZ, hrvFullZ], [-3, 1]);
      expect([restingHeartRateZeroZ, restingHeartRateFullZ], [3, -1]);
      expect([stressZeroZ, stressFullZ], [3, -1]);
      expect([spo2ZeroAt, spo2FullAt], [90, 95]);
      expect(intensityWeeklyTarget, 150);
    });
  });

  group('stress baseline', () {
    const today = LocalDate(2026, 11, 15);
    List<DailyValue> days(List<double> values) => [
      for (var i = 0; i < values.length; i++)
        (date: today.addDays(-1 - i), value: values[i]),
    ];

    test('builds until seven days are in', () {
      final result = stressBaseline(days(List.filled(6, 40)), today: today);

      expect(result, isA<BaselineBuilding>());
    });

    test('a flat history still has a spread of three points', () {
      final ready = stressBaseline(
        days(List.filled(10, 40)),
        today: today,
      ) as BaselineReady;

      expect(ready.sdOnScale, 3);
      expect(ready.compare(46).zScore, closeTo(2, 1e-9));
    });
  });
}
