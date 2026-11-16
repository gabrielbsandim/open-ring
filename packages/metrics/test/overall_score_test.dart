import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

OverallInputs inputs({
  double? fitnessPercentile = 52,
  double? restingHeartRate = 53,
  double? sleepHours = 6.6,
  double? sleepRegularity = 66,
  double? weeklyMinutes = 132,
  double strengthPerWeek = 1.5,
  double? dailySteps = 6900,
  bool olderAdult = false,
  double? waistToHeight = 0.49,
  double? bmi,
}) => OverallInputs(
  fitnessPercentile: fitnessPercentile,
  restingHeartRate: restingHeartRate,
  sleepHours: sleepHours,
  sleepRegularity: sleepRegularity,
  weeklyMinutes: weeklyMinutes,
  strengthPerWeek: strengthPerWeek,
  dailySteps: dailySteps,
  olderAdult: olderAdult,
  waistToHeight: waistToHeight,
  bmi: bmi,
);

Scored<OverallFactor> scored(OverallInputs inputs) =>
    inputs.score as Scored<OverallFactor>;

double points(OverallInputs inputs, OverallFactor factor) =>
    inputs.contributions.firstWhere((c) => c.factor == factor).points;

void main() {
  group('with every factor present', () {
    test('each factor earns its rule and the score is their sum', () {
      final all = inputs();

      expect(points(all, OverallFactor.fitness), closeTo(17.33, 0.01));
      expect(points(all, OverallFactor.restingHeartRate), closeTo(13.5, 1e-9));
      expect(points(all, OverallFactor.sleepDuration), closeTo(8, 1e-9));
      expect(points(all, OverallFactor.sleepRegularity), closeTo(6, 1e-9));
      expect(points(all, OverallFactor.movement), closeTo(14.4, 1e-9));
      expect(points(all, OverallFactor.body), closeTo(10, 1e-9));
      expect(all.coverage, 100);
      expect(all.isFull, isTrue);
      expect(scored(all).value, 69);
      expect(scored(all).missing, isEmpty);
    });

    test('nothing earns more than its weight', () {
      final best = inputs(
        fitnessPercentile: 99,
        restingHeartRate: 42,
        sleepHours: 9.5,
        sleepRegularity: 98,
        weeklyMinutes: 600,
        strengthPerWeek: 5,
        dailySteps: 20000,
        waistToHeight: 0.42,
      );

      expect(scored(best).value, 100);
    });
  });

  group('movement', () {
    test('150 minutes earn three quarters and 300 the rest', () {
      expect(inputs(weeklyMinutes: 150).movementPoints!.minutes, 7.5);
      expect(inputs(weeklyMinutes: 225).movementPoints!.minutes, 8.75);
      expect(inputs(weeklyMinutes: 300).movementPoints!.minutes, 10);
    });

    test('two strength sessions a week are full and none is zero', () {
      expect(inputs(strengthPerWeek: 2).movementPoints!.strength, 4);
      expect(inputs(strengthPerWeek: 0).movementPoints!.strength, 0);
    });

    test('steps are full at 8,000, or at 7,000 for an older adult', () {
      expect(inputs(dailySteps: 2500).movementPoints!.steps, 0);
      expect(inputs(dailySteps: 8000).movementPoints!.steps, 6);
      expect(
        inputs(dailySteps: 7000).movementPoints!.steps,
        closeTo(4.909, 0.001),
      );
      expect(
        inputs(dailySteps: 7000, olderAdult: true).movementPoints!.steps,
        6,
      );
    });

    test('is left out without minutes or without steps', () {
      expect(inputs(weeklyMinutes: null).movementPoints, isNull);
      expect(inputs(dailySteps: null).movementPoints, isNull);
      expect(scored(inputs(dailySteps: null)).missing, [
        OverallFactor.movement,
      ]);
    });
  });

  group('body', () {
    test('the waist earns everything at 0.50 or below and zero at 0.65', () {
      expect(points(inputs(waistToHeight: 0.50), OverallFactor.body), 10);
      expect(points(inputs(waistToHeight: 0.41), OverallFactor.body), 10);
      expect(points(inputs(waistToHeight: 0.65), OverallFactor.body), 0);
      expect(
        points(inputs(waistToHeight: 0.575), OverallFactor.body),
        closeTo(5, 1e-9),
      );
    });

    test('without the waist, weight and height are worth 5 points', () {
      final healthy = inputs(waistToHeight: null, bmi: 23);
      final high = inputs(waistToHeight: null, bmi: 30);

      expect(points(healthy, OverallFactor.body), 5);
      expect(healthy.coverage, 95);
      expect(points(high, OverallFactor.body), closeTo(2.5, 1e-9));
    });

    test('the waist wins when both are known', () {
      final both = inputs(bmi: 31);

      expect(points(both, OverallFactor.body), 10);
      expect(both.coverage, 100);
    });

    test('a value under the healthy range removes the factor', () {
      final lowWaist = inputs(waistToHeight: 0.39);
      final lowBmi = inputs(waistToHeight: null, bmi: 18.4);

      expect(scored(lowWaist).missing, [OverallFactor.body]);
      expect(scored(lowBmi).missing, [OverallFactor.body]);
      expect(lowWaist.coverage, 90);
    });
  });

  group('a missing factor', () {
    test('is left out and the rest is rescaled', () {
      final noFitness = inputs(fitnessPercentile: null);

      expect(noFitness.coverage, 70);
      expect(noFitness.isFull, isFalse);
      expect(scored(noFitness).value, 74);
      expect(scored(noFitness).missing, [OverallFactor.fitness]);
    });

    test('never lowers the score of someone at the top', () {
      final best = inputs(
        fitnessPercentile: null,
        restingHeartRate: 48,
        sleepHours: 8,
        sleepRegularity: 92,
        weeklyMinutes: 320,
        strengthPerWeek: 2,
        dailySteps: 9000,
        waistToHeight: null,
      );

      expect(scored(best).value, 100);
    });
  });

  group('is not scored', () {
    test('under 50 points of coverage', () {
      final thin = inputs(
        fitnessPercentile: null,
        sleepRegularity: null,
        waistToHeight: null,
      );

      expect(thin.coverage, 45);
      expect(thin.score, isA<InsufficientData<OverallFactor>>());
      expect((thin.score as InsufficientData<OverallFactor>).missing, [
        OverallFactor.fitness,
        OverallFactor.sleepRegularity,
        OverallFactor.body,
      ]);
    });

    test('without fitness and without resting heart rate', () {
      final noHeart = inputs(fitnessPercentile: null, restingHeartRate: null);

      expect(noHeart.coverage, 55);
      expect(noHeart.score, isA<InsufficientData<OverallFactor>>());
    });

    test('without any sleep factor', () {
      final noSleep = inputs(sleepHours: null, sleepRegularity: null);

      expect(noSleep.coverage, 75);
      expect(noSleep.score, isA<InsufficientData<OverallFactor>>());
    });

    test('still reports what each present factor earned', () {
      final noSleep = inputs(sleepHours: null, sleepRegularity: null);

      expect(points(noSleep, OverallFactor.restingHeartRate), 13.5);
    });
  });

  test('bands cut at 85, 70 and 55', () {
    expect(overallBand(100), OverallBand.strong);
    expect(overallBand(85), OverallBand.strong);
    expect(overallBand(84), OverallBand.solid);
    expect(overallBand(70), OverallBand.solid);
    expect(overallBand(69), OverallBand.building);
    expect(overallBand(55), OverallBand.building);
    expect(overallBand(54), OverallBand.start);
    expect(overallBand(0), OverallBand.start);
  });

  test('the weights add up to 100', () {
    expect(
      OverallFactor.values.fold<double>(0, (sum, f) => sum + f.weight),
      100,
    );
    expect(
      movementMinutesWeight + movementStrengthWeight + movementStepsWeight,
      OverallFactor.movement.weight,
    );
  });
}
