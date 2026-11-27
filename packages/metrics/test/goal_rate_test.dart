import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const blockStart = LocalDate(2026, 11, 16);
const today = LocalDate(2026, 12, 7);
const tight = 1e-9;

final GoalBlock block = goalBlock(
  startKg: 78.4,
  percentPerWeek: 0.5,
  start: blockStart,
);

const caseFourRate = WeightRateReady(
  perWeek: -0.2958,
  low: -0.3881,
  high: -0.2034,
);

LossRate fromPercents(double low, double high) => LossRate(
  kg: (low + high) / 2,
  kgLow: low,
  kgHigh: high,
  percent: (low + high) / 2,
  percentLow: low,
  percentHigh: high,
);

LossRate fromKg(double low, double high, double trendKg) => LossRate(
  kg: (low + high) / 2,
  kgLow: low,
  kgHigh: high,
  percent: (low + high) / 2 / trendKg * 100,
  percentLow: low / trendKg * 100,
  percentHigh: high / trendKg * 100,
);

ArrivalRange? arrival({
  required double trendKg,
  required double referenceKg,
  required LossRate rate,
  LocalDate when = today,
  GoalBlock? within,
}) => arrivalRange(
  trendKg: trendKg,
  referenceKg: referenceKg,
  rate: rate,
  today: when,
  block: within ?? block,
);

WeightGoalRefusal? refusal({
  int? age = 34,
  double? heightCm = 178,
  double trendKg = 78.4,
  bool pregnant = false,
}) => weightGoalRefusal(
  age: age,
  heightCm: heightCm,
  trendKg: trendKg,
  pregnantOrBreastfeeding: pregnant,
);

void main() {
  group('bmi and lossCapPercent', () {
    test('78.4 kg at 178 cm is a bmi of 24.744 with a cap of 0.5', () {
      final value = bmi(78.4, 178);
      expect(value, closeTo(24.744, 1e-3));
      expect(lossCapPercent(value), closeTo(0.5, tight));
    });

    test(
      'the cap steps at 25 and at 30, each bound belonging to the upper',
      () {
        expect(lossCapPercent(24.99), closeTo(0.5, tight));
        expect(lossCapPercent(25), closeTo(0.75, tight));
        expect(lossCapPercent(29.99), closeTo(0.75, tight));
        expect(lossCapPercent(30), closeTo(1, tight));
      },
    );

    test('exact bmi boundaries come out exact at 200 cm', () {
      expect(bmi(100, 200), 25);
      expect(bmi(120, 200), 30);
      expect(lossCapPercent(bmi(100, 200)), closeTo(0.75, tight));
      expect(lossCapPercent(bmi(120, 200)), closeTo(1, tight));
    });
  });

  group('goalPacePercent', () {
    test('standard is 0.5 and gentle is 0.25', () {
      expect(goalPacePercent(GoalPace.standard), closeTo(0.5, tight));
      expect(goalPacePercent(GoalPace.gentle), closeTo(0.25, tight));
    });
  });

  group('goalBlock', () {
    test('a standard block runs twelve weeks then four of maintenance', () {
      expect(block.start, blockStart);
      expect(block.weeks, 12);
      expect(block.weeklyKg, closeTo(0.392, tight));
      expect(block.blockKg, closeTo(4.704, tight));
      expect(block.end, const LocalDate(2027, 2, 7));
      expect(block.maintenanceEnd, const LocalDate(2027, 3, 7));
    });

    test('a gentle block halves the weekly kilos and keeps the dates', () {
      final gentle = goalBlock(
        startKg: 78.4,
        percentPerWeek: 0.25,
        start: blockStart,
      );
      expect(gentle.weeks, 12);
      expect(gentle.weeklyKg, closeTo(0.196, tight));
      expect(gentle.blockKg, closeTo(2.352, tight));
      expect(gentle.end, const LocalDate(2027, 2, 7));
      expect(gentle.maintenanceEnd, const LocalDate(2027, 3, 7));
    });

    test('a fast pace shortens the block to hold the ten percent ceiling', () {
      final fast = goalBlock(
        startKg: 120,
        percentPerWeek: 1,
        start: blockStart,
      );
      expect(fast.weeks, 10);
      expect(fast.weeklyKg, closeTo(1.2, tight));
      expect(fast.blockKg, closeTo(12, tight));
      expect(fast.end, const LocalDate(2027, 1, 24));
      expect(fast.maintenanceEnd, const LocalDate(2027, 2, 21));
    });

    test('at 0.75 percent the block is still twelve weeks', () {
      final block075 = goalBlock(
        startKg: 120,
        percentPerWeek: 0.75,
        start: blockStart,
      );
      expect(block075.weeks, 12);
    });
  });

  group('lossRate', () {
    test('the slope turns into a loss and its ends swap', () {
      final rate = lossRate(caseFourRate, 77.782);
      expect(rate.kg, closeTo(0.2958, tight));
      expect(rate.kgLow, closeTo(0.2034, tight));
      expect(rate.kgHigh, closeTo(0.3881, tight));
      expect(rate.percent, closeTo(0.3803, 1e-4));
      expect(rate.percentLow, closeTo(0.2615, 1e-4));
      expect(rate.percentHigh, closeTo(0.4990, 1e-4));
    });
  });

  group('pathState', () {
    final rate = lossRate(caseFourRate, 77.782);

    test('the worked rate is on track at both paces', () {
      expect(
        pathState(rate, targetPercent: 0.5, capPercent: 0.5),
        PathState.onTrack,
      );
      expect(
        pathState(rate, targetPercent: 0.25, capPercent: 0.5),
        PathState.onTrack,
      );
    });

    test('no rate yet is building', () {
      expect(
        pathState(null, targetPercent: 0.5, capPercent: 0.5),
        PathState.building,
      );
    });

    test('a high end under half the target is below', () {
      expect(
        pathState(
          fromPercents(0.10, 0.24),
          targetPercent: 0.5,
          capPercent: 0.5,
        ),
        PathState.below,
      );
    });

    test('a high end exactly at half the target is on track', () {
      expect(
        pathState(
          fromPercents(0.10, 0.25),
          targetPercent: 0.5,
          capPercent: 0.5,
        ),
        PathState.onTrack,
      );
    });

    test('a low end over one and a half targets is above, under the cap', () {
      final fast = fromPercents(0.40, 0.60);
      expect(
        pathState(fast, targetPercent: 0.25, capPercent: 0.5),
        PathState.above,
      );
      expect(overCap(fast, 0.5), isFalse);
    });

    test('a low end exactly at one and a half targets is on track', () {
      expect(
        pathState(
          fromPercents(0.375, 0.6),
          targetPercent: 0.25,
          capPercent: 0.5,
        ),
        PathState.onTrack,
      );
    });

    test('a low end over the cap is above and over the cap', () {
      final over = fromPercents(0.60, 0.80);
      expect(
        pathState(over, targetPercent: 0.5, capPercent: 0.5),
        PathState.above,
      );
      expect(overCap(over, 0.5), isTrue);
    });

    test('a low end exactly at the cap is on track and not over it', () {
      final atCap = fromPercents(0.50, 0.70);
      expect(
        pathState(atCap, targetPercent: 0.5, capPercent: 0.5),
        PathState.onTrack,
      );
      expect(overCap(atCap, 0.5), isFalse);
    });

    test('a higher cap leaves a fast rate above but not over the cap', () {
      final fast = fromPercents(0.80, 0.90);
      expect(
        pathState(fast, targetPercent: 0.5, capPercent: 1),
        PathState.above,
      );
      expect(overCap(fast, 1), isFalse);
    });

    test('the cap is checked before below', () {
      expect(
        pathState(fromPercents(0.30, 0.40), targetPercent: 1, capPercent: 0.2),
        PathState.above,
      );
    });
  });

  group('arrivalRange', () {
    final worked = lossRate(caseFourRate, 77.782);

    test('a wait after the block gives the worked range', () {
      final range = arrival(trendKg: 77.782, referenceKg: 74, rate: worked)!;
      expect(range.earliestWeeks, closeTo(13.7449, 1e-3));
      expect(range.earliest, const LocalDate(2027, 3, 13));
      expect(range.latestWeeks, closeTo(22.5939, 1e-3));
      expect(range.latest, const LocalDate(2027, 5, 14));
    });

    test('a goal inside the block needs no wait', () {
      final range = arrival(
        trendKg: 80,
        referenceKg: 78,
        rate: fromKg(0.25, 0.5, 80),
      )!;
      expect(range.earliestWeeks, closeTo(4, 1e-3));
      expect(range.earliest, const LocalDate(2027, 1, 4));
      expect(range.latestWeeks, closeTo(8, 1e-3));
      expect(range.latest, const LocalDate(2027, 2, 1));
    });

    test(
      'exactly the weeks left fit with no wait, and half a day rounds up',
      () {
        final range = arrival(
          trendKg: 80,
          referenceKg: 77.75,
          rate: fromKg(0.25, 0.5, 80),
        )!;
        expect(range.latestWeeks, closeTo(9, 1e-3));
        expect(range.latest, const LocalDate(2027, 2, 8));
        expect(range.earliestWeeks, closeTo(4.5, 1e-3));
        expect(range.earliest, const LocalDate(2027, 1, 8));
      },
    );

    test('later blocks use the weeks of the block', () {
      final fast = goalBlock(
        startKg: 120,
        percentPerWeek: 1,
        start: blockStart,
      );
      final range = arrival(
        trendKg: 118,
        referenceKg: 108,
        rate: fromKg(0.5, 1, 118),
        when: const LocalDate(2026, 11, 30),
        within: fast,
      )!;
      expect(range.earliestWeeks, closeTo(14, 1e-3));
      expect(range.earliest, const LocalDate(2027, 3, 8));
      expect(range.latestWeeks, closeTo(28, 1e-3));
      expect(range.latest, const LocalDate(2027, 6, 14));
    });

    test('a loss of zero or less has no arrival', () {
      expect(
        arrival(
          trendKg: 77.782,
          referenceKg: 74,
          rate: fromKg(0, 0.3881, 77.782),
        ),
        isNull,
      );
      expect(
        arrival(
          trendKg: 77.782,
          referenceKg: 74,
          rate: fromKg(-0.1, 0.3881, 77.782),
        ),
        isNull,
      );
    });

    test('a trend at or under the reference has no arrival', () {
      expect(arrival(trendKg: 74, referenceKg: 74, rate: worked), isNull);
      expect(arrival(trendKg: 73, referenceKg: 74, rate: worked), isNull);
    });

    test('a latest end more than a year after the earliest has no arrival', () {
      expect(
        arrival(
          trendKg: 77.782,
          referenceKg: 74,
          rate: fromKg(0.01, 0.3881, 77.782),
        ),
        isNull,
      );
    });

    test('ends two year numbers apart have no arrival', () {
      expect(
        arrival(
          trendKg: 80,
          referenceKg: 79,
          rate: fromKg(0.02, 7, 80),
          when: const LocalDate(2026, 12, 20),
        ),
        isNull,
      );
    });

    test('a latest end in the next calendar year still has an arrival', () {
      final range = arrival(
        trendKg: 77.782,
        referenceKg: 74,
        rate: fromKg(0.05, 0.3881, 77.782),
      )!;
      expect(range.latest, const LocalDate(2028, 11, 3));
    });

    test('a day after the block end counts no weeks left', () {
      final range = arrival(
        trendKg: 80,
        referenceKg: 78,
        rate: fromKg(0.25, 0.5, 80),
        when: const LocalDate(2027, 3, 1),
      )!;
      expect(range.earliestWeeks, closeTo(8, 1e-3));
      expect(range.earliest, const LocalDate(2027, 4, 26));
      expect(range.latestWeeks, closeTo(12, 1e-3));
      expect(range.latest, const LocalDate(2027, 5, 24));
    });

    test('a day long after the block end never counts negative weeks', () {
      final range = arrival(
        trendKg: 80,
        referenceKg: 75,
        rate: fromKg(0.5, 0.5, 80),
        when: const LocalDate(2027, 3, 1),
      )!;
      expect(range.earliestWeeks, closeTo(14, 1e-3));
      expect(range.latestWeeks, closeTo(14, 1e-3));
      expect(range.latest, const LocalDate(2027, 6, 7));
    });

    test('six blocks after the one under way still give an arrival', () {
      final range = arrival(
        trendKg: 112,
        referenceKg: 70,
        rate: fromKg(0.5, 0.5, 112),
        when: blockStart,
      )!;
      expect(range.latestWeeks, closeTo(108, 1e-3));
      expect(range.latest, const LocalDate(2028, 12, 11));
      expect(
        arrival(
          trendKg: 112.5,
          referenceKg: 70,
          rate: fromKg(0.5, 0.5, 112.5),
          when: blockStart,
        ),
        isNull,
      );
    });

    test('an end far past the blocks allowed has no arrival', () {
      expect(
        arrival(trendKg: 100, referenceKg: 70, rate: fromKg(0.25, 0.3, 100)),
        isNull,
      );
      expect(
        arrival(
          trendKg: 120,
          referenceKg: 60,
          rate: fromKg(0.5, 0.5, 120),
          when: blockStart,
        ),
        isNull,
      );
    });

    test('a loss barely above zero has no arrival and does not throw', () {
      for (final low in [1e-8, 1e-300, 4.9e-324]) {
        expect(
          arrival(trendKg: 80, referenceKg: 70, rate: fromKg(low, 0.5, 80)),
          isNull,
        );
      }
    });

    test('a day before the block start counts at most the block weeks', () {
      final range = arrival(
        trendKg: 80,
        referenceKg: 76.25,
        rate: fromKg(0.25, 0.5, 80),
        when: const LocalDate(2026, 10, 1),
      )!;
      expect(range.earliestWeeks, closeTo(7.5, 1e-3));
      expect(range.earliest, const LocalDate(2026, 11, 23));
      expect(range.latestWeeks, closeTo(19, 1e-3));
      expect(range.latest, const LocalDate(2027, 2, 11));
    });
  });

  group('referenceFloorKg', () {
    test('the lowest weight at the floor bmi, up to the next half kilo', () {
      expect(referenceFloorKg(178), closeTo(59, tight));
      expect(referenceFloorKg(170), closeTo(53.5, tight));
    });

    test('an exact multiple of half a kilo stays', () {
      expect(referenceFloorKg(200), closeTo(74, tight));
    });
  });

  group('weightGoalRefusal', () {
    test('a missing age wins, even with a missing height', () {
      expect(refusal(age: null, heightCm: null), WeightGoalRefusal.ageMissing);
    });

    test('under eighteen wins over pregnancy', () {
      expect(refusal(age: 17, pregnant: true), WeightGoalRefusal.under18);
    });

    test('eighteen is allowed', () {
      expect(refusal(age: 18), isNull);
    });

    test('a missing height is refused', () {
      expect(refusal(heightCm: null), WeightGoalRefusal.heightMissing);
    });

    test('pregnancy wins over a low bmi', () {
      expect(
        refusal(pregnant: true, trendKg: 57.9),
        WeightGoalRefusal.pregnancy,
      );
    });

    test('a bmi under the floor is refused', () {
      expect(refusal(trendKg: 57.9), WeightGoalRefusal.bmiUnderFloor);
    });

    test('a bmi of exactly the floor passes', () {
      expect(refusal(heightCm: 200, trendKg: 74), isNull);
    });

    test('the defaults pass', () {
      expect(refusal(), isNull);
    });
  });

  group('softMode', () {
    test('two yes answers turn it on, fewer do not', () {
      expect(softMode(0), isFalse);
      expect(softMode(1), isFalse);
      expect(softMode(2), isTrue);
      expect(softMode(5), isTrue);
    });
  });

  group('the metrics library exports', () {
    test('every constant of the goal rate', () {
      expect(goalStandardPercent, 0.5);
      expect(goalGentlePercent, 0.25);
      expect(goalCapBmiMid, 25.0);
      expect(goalCapBmiHigh, 30.0);
      expect(goalBlockWeeks, 12);
      expect(goalBlockMaxLossPercent, 10.0);
      expect(goalMaintenanceWeeks, 4);
      expect(goalBandLow, 0.5);
      expect(goalBandHigh, 1.5);
      expect(goalArrivalMaxBlocks, 6);
      expect(goalReferenceStepKg, 0.5);
      expect(goalMinAge, 18);
      expect(goalSoftModeYes, 2);
    });

    test('every enum of the goal rate', () {
      expect(GoalKind.values, [
        GoalKind.loseFat,
        GoalKind.getFitter,
        GoalKind.sleepBetter,
      ]);
      expect(GoalPace.values, [GoalPace.standard, GoalPace.gentle]);
      expect(PathState.values, [
        PathState.building,
        PathState.above,
        PathState.onTrack,
        PathState.below,
      ]);
      expect(WeightGoalRefusal.values, [
        WeightGoalRefusal.ageMissing,
        WeightGoalRefusal.under18,
        WeightGoalRefusal.heightMissing,
        WeightGoalRefusal.pregnancy,
        WeightGoalRefusal.bmiUnderFloor,
      ]);
    });
  });
}
