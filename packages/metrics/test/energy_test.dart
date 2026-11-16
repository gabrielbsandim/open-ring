import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

void main() {
  double? resting({
    EnergySex? sex = EnergySex.male,
    int? age = 34,
    double? kilograms = 78.4,
    double? centimeters = 178,
  }) => restingEnergy(
    sex: sex,
    age: age,
    kilograms: kilograms,
    centimeters: centimeters,
  );

  group('restingEnergy', () {
    test('a man of 34, 178 cm and 78.4 kg burns 1733.4 kcal a day', () {
      expect(resting(), closeTo(1733.436, 0.001));
    });

    test('a woman of the same size burns 166 kcal less', () {
      expect(resting(sex: EnergySex.female), closeTo(1567.436, 0.001));
    });

    test('a missing field gives no estimate', () {
      expect(resting(sex: null), isNull);
      expect(resting(age: null), isNull);
      expect(resting(kilograms: null), isNull);
      expect(resting(centimeters: null), isNull);
    });

    test('the estimate starts at 18', () {
      expect(resting(age: 17), isNull);
      expect(resting(age: 18), isNotNull);
    });
  });

  group('energyRange', () {
    test('the resting figure is shown as 1550 to 1900', () {
      expect(energyRange(resting()!, energyRestingMargin), (
        low: 1550,
        high: 1900,
      ));
    });

    test('an end halfway between two steps rounds up', () {
      expect(energyRange(1025, 0), (low: 1050, high: 1050));
      expect(energyRange(1024, 0), (low: 1000, high: 1000));
      expect(energyRange(1075, 0), (low: 1100, high: 1100));
    });

    test('the margin is taken on the total, not on rounded parts', () {
      expect(energyRange(1020 + 1020, 0), (low: 2050, high: 2050));
    });

    test('nothing burned is a range of zero', () {
      expect(energyRange(0, energyDayMargin), (low: 0, high: 0));
    });
  });

  group('baseEnergy', () {
    test('a whole day is the resting figure times 1.3', () {
      final day = baseEnergy(resting()!, const Duration(hours: 24));

      expect(day, closeTo(2253.467, 0.001));
    });

    test('it is spread evenly over the day', () {
      final day = baseEnergy(2400, const Duration(hours: 24));

      expect(
        baseEnergy(2400, const Duration(hours: 6)),
        closeTo(day / 4, 1e-9),
      );
      expect(baseEnergy(2400, Duration.zero), 0);
    });

    test('a negative time burns nothing', () {
      expect(baseEnergy(2400, const Duration(hours: -1)), 0);
    });
  });

  group('stepEnergy', () {
    test('one step of the persona costs 0.029 kcal', () {
      final step = stepEnergy(steps: 1, kilograms: 78.4, centimeters: 178);

      expect(step, closeTo(0.02896, 0.00001));
    });

    test('ten thousand steps cost ten thousand times one', () {
      final walked = stepEnergy(
        steps: 10000,
        kilograms: 78.4,
        centimeters: 178,
      );

      expect(walked, closeTo(289.57, 0.01));
    });

    test('no steps cost nothing', () {
      expect(stepEnergy(steps: 0, kilograms: 78.4, centimeters: 178), 0);
    });
  });

  group('workoutEnergy', () {
    double workout(double met, Duration elapsed) =>
        workoutEnergy(met: met, kilograms: 78.4, elapsed: elapsed);

    test('26.5 minutes at 9.8 MET cost about 305 kcal', () {
      final run = workout(9.8, const Duration(minutes: 26, seconds: 30));

      expect(run, closeTo(304.7, 0.1));
    });

    test('rest costs nothing above rest', () {
      expect(workout(1, const Duration(hours: 1)), 0);
    });

    test('an intensity under rest never goes negative', () {
      expect(workout(0.9, const Duration(hours: 1)), 0);
    });

    test('no time costs nothing', () {
      expect(workout(9.8, Duration.zero), 0);
    });
  });
}
