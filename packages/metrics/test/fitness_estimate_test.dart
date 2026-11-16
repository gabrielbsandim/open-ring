import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const day = LocalDate(2026, 11, 9);

FitnessStretch stretch({
  int minutes = 20,
  double metersPerMinute = 160,
  double meanBpm = 150,
}) => (
  duration: Duration(minutes: minutes),
  meters: metersPerMinute * minutes,
  meanBpm: meanBpm,
);

FitnessEffort run(int daysBefore, List<FitnessStretch> stretches) => (
  date: day.addDays(-daysBefore),
  gait: FitnessGait.run,
  stretches: stretches,
);

double? vo2(FitnessStretch value, {FitnessGait gait = FitnessGait.run}) =>
    effortVo2max(
      (date: day, gait: gait, stretches: [value]),
      restingBpm: 50,
      maxBpm: 190,
    );

void main() {
  group('the percentile', () {
    test('every cell of the table returns its percentile', () {
      const men30 = [27.2, 30.2, 35.9, 42.4, 49.2, 56.5, 59.8];
      const women60 = [13.4, 14.6, 17.2, 20.0, 23.8, 27.0, 29.4];

      for (var i = 0; i < fitnessPercentiles.length; i++) {
        expect(
          fitnessPercentile(men30[i], age: 35, sex: FitnessSex.male),
          closeTo(fitnessPercentiles[i], 1e-9),
        );
        expect(
          fitnessPercentile(women60[i], age: 69, sex: FitnessSex.female),
          closeTo(fitnessPercentiles[i], 1e-9),
        );
      }
      expect(fitnessPercentile(48, age: 25, sex: FitnessSex.male), 50);
      expect(fitnessPercentile(18.3, age: 79, sex: FitnessSex.female), 50);
    });

    test('interpolates between two cells', () {
      expect(
        fitnessPercentile(45.8, age: 35, sex: FitnessSex.male),
        closeTo(62.5, 1e-9),
      );
    });

    test('is clamped to 5 and 95', () {
      expect(fitnessPercentile(10, age: 35, sex: FitnessSex.male), 5);
      expect(fitnessPercentile(90, age: 35, sex: FitnessSex.male), 95);
    });

    test('is null outside 20 to 79 years', () {
      expect(fitnessPercentile(40, age: 19, sex: FitnessSex.male), isNull);
      expect(fitnessPercentile(40, age: 80, sex: FitnessSex.male), isNull);
      expect(fitnessPercentile(40, age: 20, sex: FitnessSex.male), isNotNull);
      expect(fitnessPercentile(40, age: 79, sex: FitnessSex.male), isNotNull);
    });

    test('the decade changes at 30, not at 29', () {
      expect(fitnessPercentile(48, age: 29, sex: FitnessSex.male), 50);
      expect(
        fitnessPercentile(48, age: 30, sex: FitnessSex.male),
        greaterThan(50),
      );
    });
  });

  group('a steady effort', () {
    test('running scales the cost of the speed by the reserve used', () {
      // 160 m/min costs 3.5 + 32; 150 bpm is 100 of 140 beats of reserve.
      expect(vo2(stretch()), closeTo(3.5 + 32 / (100 / 140), 1e-9));
    });

    test('walking uses the walking cost', () {
      final value = vo2(
        stretch(metersPerMinute: 90, meanBpm: 134),
        gait: FitnessGait.walk,
      );

      expect(value, closeTo(3.5 + 9 / 0.6, 1e-9));
    });

    test('is null outside 60 to 90 percent of the reserve', () {
      expect(vo2(stretch(meanBpm: 133)), isNull);
      expect(vo2(stretch(meanBpm: 134)), isNotNull);
      expect(vo2(stretch(meanBpm: 176)), isNotNull);
      expect(vo2(stretch(meanBpm: 177)), isNull);
    });

    test('is null at or below the resting heart rate', () {
      expect(vo2(stretch(meanBpm: 50)), isNull);
      expect(vo2(stretch(meanBpm: 40)), isNull);
    });

    test('is null when the maximum is not above the resting value', () {
      expect(
        steadyVo2max(
          gait: FitnessGait.run,
          metersPerMinute: 160,
          meanBpm: 150,
          restingBpm: 60,
          maxBpm: 60,
        ),
        isNull,
      );
    });

    test('a walk faster than a walk, or a run slower than a jog, is null', () {
      expect(
        vo2(stretch(metersPerMinute: 101), gait: FitnessGait.walk),
        isNull,
      );
      expect(vo2(stretch(metersPerMinute: 49), gait: FitnessGait.walk), isNull);
      expect(vo2(stretch(metersPerMinute: 79)), isNull);
      expect(vo2(stretch(metersPerMinute: 80)), isNotNull);
    });

    test('a stretch under 10 minutes is ignored', () {
      expect(vo2(stretch(minutes: 9)), isNull);
      expect(vo2(stretch(minutes: 10)), isNotNull);
    });
  });

  group('a workout', () {
    test('is the median of its steady stretches', () {
      final effort = run(1, [
        stretch(metersPerMinute: 150),
        stretch(),
        stretch(metersPerMinute: 200),
        stretch(minutes: 5, metersPerMinute: 300, meanBpm: 151),
      ]);

      expect(
        effortVo2max(effort, restingBpm: 50, maxBpm: 190),
        closeTo(vo2(stretch())!, 1e-9),
      );
    });

    test('without a steady stretch gives nothing', () {
      expect(
        effortVo2max(
          run(1, [stretch(minutes: 4)]),
          restingBpm: 50,
          maxBpm: 190,
        ),
        isNull,
      );
    });
  });

  group('the best of 90 days', () {
    double? best(List<FitnessEffort> efforts) =>
        bestVo2max(efforts, day: day, restingBpm: 50, maxBpm: 190);

    test('is the highest workout, not the latest', () {
      expect(
        best([
          run(40, [stretch(metersPerMinute: 180)]),
          run(2, [stretch(metersPerMinute: 150)]),
        ]),
        closeTo(vo2(stretch(metersPerMinute: 180))!, 1e-9),
      );
    });

    test('an effort 91 days old is ignored and one 90 days old counts', () {
      expect(
        best([
          run(91, [stretch()]),
        ]),
        isNull,
      );
      expect(
        best([
          run(90, [stretch()]),
        ]),
        isNotNull,
      );
    });

    test('an effort on the day itself or after it is not read', () {
      expect(
        best([
          run(0, [stretch()]),
        ]),
        isNull,
      );
      expect(
        best([
          run(-1, [stretch()]),
        ]),
        isNull,
      );
    });

    test('no effort gives nothing', () {
      expect(best([]), isNull);
    });
  });
}
