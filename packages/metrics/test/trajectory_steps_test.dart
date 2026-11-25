import 'dart:math' as math;

import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

StepsWhatIf whatIf(
  int extra, {
  int typical = 8700,
  double kilograms = 77.6045,
  double centimeters = 178,
}) => stepsWhatIf(
  extraSteps: extra,
  typicalSteps: typical,
  kilograms: kilograms,
  centimeters: centimeters,
);

void main() {
  group('the constants', () {
    test('24 kcal per kg a day', () {
      expect(trajectoryKcalPerKgDay, 24.0);
    });

    test('the cohort words run from the least to the most', () {
      expect(CohortWords.values, [
        CohortWords.aboutTheSame,
        CohortWords.slightlyLower,
        CohortWords.fifthToQuarterLower,
        CohortWords.muchLower,
      ]);
    });
  });

  group('paluchHazard anchors and the curve between them', () {
    test('each anchor gives its hazard ratio', () {
      expect(paluchHazard(3553), closeTo(1.0, 1e-9));
      expect(paluchHazard(5801), closeTo(0.60, 1e-9));
      expect(paluchHazard(7842), closeTo(0.55, 1e-9));
      expect(paluchHazard(10901), closeTo(0.47, 1e-9));
    });

    test('at or below the first anchor it is 1.0', () {
      expect(paluchHazard(3552), 1.0);
      expect(paluchHazard(0), 1.0);
    });

    test('at or above the last anchor it is 0.47', () {
      expect(paluchHazard(10902), closeTo(0.47, 1e-9));
      expect(paluchHazard(30000), closeTo(0.47, 1e-9));
    });

    test('the log of the ratio is linear between anchors', () {
      const mid = (3553 + 5801) ~/ 2;
      const f = (mid - 3553) / (5801 - 3553);
      expect(paluchHazard(mid), closeTo(math.exp(f * math.log(0.6)), 1e-9));
      expect(paluchHazard(8700), closeTo(0.5262783554, 1e-6));
      expect(paluchHazard(10000), closeTo(0.4922714276, 1e-6));
    });

    test('it never rises with more steps', () {
      var previous = paluchHazard(0);
      for (var steps = 500; steps <= 12000; steps += 500) {
        final hazard = paluchHazard(steps);
        expect(hazard, lessThanOrEqualTo(previous));
        previous = hazard;
      }
    });
  });

  group('4. +2000 steps at 8700 typical', () {
    final result = whatIf(2000);

    test('the walk is 1.4774 km and 57.33 kcal a day', () {
      expect(result.kilometers, closeTo(1.4774, 0.0001));
      expect(result.kcalPerDay, closeTo(57.33, 0.01));
    });

    test('it ends at 10700 steps, not clamped', () {
      expect(result.toSteps, 10700);
      expect(result.clamped, isFalse);
    });

    test('12 weeks less is 0.4910 kg and 4 weeks 0.1764 kg', () {
      expect(result.kgLess12, closeTo(0.4910, 0.0001));
      expect(result.kgLess4, closeTo(0.1764, 0.0001));
    });

    test('the hazard falls from 0.5263 to 0.4749, 9.766 percent lower', () {
      expect(result.hazardFrom, closeTo(0.5263, 0.0001));
      expect(result.hazardTo, closeTo(0.4749, 0.0001));
      expect(result.percentLower, closeTo(9.766, 0.001));
    });

    test('the words are slightlyLower', () {
      expect(result.words, CohortWords.slightlyLower);
    });
  });

  group('5. +1000 and +3000', () {
    test('+1000 gives 0.2455 kg in 12 weeks and 5.009 percent', () {
      final result = whatIf(1000);
      expect(result.kgLess12, closeTo(0.2455, 0.0001));
      expect(result.percentLower, closeTo(5.009, 0.001));
      expect(result.clamped, isFalse);
    });

    test('+1000 sits 0.009 above the 5 percent line, slightlyLower', () {
      final result = whatIf(1000);
      expect(result.percentLower, greaterThan(5));
      expect(result.words, CohortWords.slightlyLower);
    });

    test('+3000 lands on the last anchor, clamped, 10.694 percent', () {
      final result = whatIf(3000);
      expect(result.toSteps, 11700);
      expect(result.hazardTo, closeTo(0.47, 1e-9));
      expect(result.percentLower, closeTo(10.694, 0.001));
      expect(result.clamped, isTrue);
    });

    test('the kcal still follows the full extra, past the clamp', () {
      expect(whatIf(3000).kcalPerDay, closeTo(85.99, 0.01));
    });
  });

  group('clamped is toSteps > 10901', () {
    test('landing exactly on 10901 is not clamped', () {
      expect(whatIf(2201).toSteps, 10901);
      expect(whatIf(2201).clamped, isFalse);
    });

    test('one step past 10901 is clamped', () {
      expect(whatIf(2202).clamped, isTrue);
    });
  });

  group('typical steps above 10901 give 0 percent', () {
    test('12000 plus 1000 is 0 percent, aboutTheSame and clamped', () {
      final result = whatIf(1000, typical: 12000);
      expect(result.hazardFrom, closeTo(0.47, 1e-9));
      expect(result.hazardTo, closeTo(0.47, 1e-9));
      expect(result.percentLower, closeTo(0, 1e-9));
      expect(result.words, CohortWords.aboutTheSame);
      expect(result.clamped, isTrue);
    });
  });

  group('the cohort words by percent lower', () {
    test('zero extra steps is 0 percent, 0 kcal, aboutTheSame', () {
      final result = whatIf(0);
      expect(result.percentLower, closeTo(0, 1e-9));
      expect(result.kcalPerDay, 0);
      expect(result.kgLess12, 0);
      expect(result.words, CohortWords.aboutTheSame);
    });

    test('under 5 percent is aboutTheSame', () {
      final result = whatIf(500, typical: 10000);
      expect(result.percentLower, closeTo(2.55, 0.05));
      expect(result.words, CohortWords.aboutTheSame);
    });

    test('5 to 15 percent is slightlyLower', () {
      final result = whatIf(2041, typical: 5801);
      expect(result.percentLower, closeTo(8.33, 0.01));
      expect(result.words, CohortWords.slightlyLower);
    });

    test('15 to 30 percent is fifthToQuarterLower', () {
      final result = whatIf(1000, typical: 3553);
      expect(result.percentLower, closeTo(20.3, 0.1));
      expect(result.words, CohortWords.fifthToQuarterLower);
    });

    test('30 percent or more is muchLower', () {
      final result = whatIf(2248, typical: 3553);
      expect(result.percentLower, closeTo(40, 0.01));
      expect(result.words, CohortWords.muchLower);
    });
  });

  group('negative inputs throw ArgumentError', () {
    test('extraSteps', () {
      expect(() => whatIf(-1), throwsArgumentError);
    });

    test('typicalSteps', () {
      expect(() => whatIf(1000, typical: -1), throwsArgumentError);
    });

    test('kilograms', () {
      expect(() => whatIf(1000, kilograms: -1), throwsArgumentError);
    });

    test('centimeters', () {
      expect(() => whatIf(1000, centimeters: -1), throwsArgumentError);
    });
  });
}
