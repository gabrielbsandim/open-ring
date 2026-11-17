import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const LossRate _onTrack = LossRate(
  kg: 0.2958,
  kgLow: 0.2034,
  kgHigh: 0.3881,
  percent: 0.380,
  percentLow: 0.261,
  percentHigh: 0.499,
);

const LeverBaseline _baseline = LeverBaseline(
  stepsMedian14: 8000,
  bedMedian: 705,
  wakeMedian: 405,
  effortMean4Weeks: null,
  strengthDaysUsual: 1,
);

const List<LeverWeek> _levers = [
  LeverWeek(lever: Lever(kind: LeverKind.strengthDays, target: 2), achieved: 2),
  LeverWeek(
    lever: Lever(kind: LeverKind.sleepWindow, target: 690),
    achieved: 6,
  ),
  LeverWeek(lever: Lever(kind: LeverKind.steps, target: 9000), achieved: 5),
];

// A block that starts on a Tuesday ends on a Monday, so the Monday that equals
// block.end exists: 2027-02-08.
GoalBlock _block() => goalBlock(
  startKg: 100,
  percentPerWeek: 0.5,
  start: const LocalDate(2026, 11, 17),
);

const LocalDate _end = LocalDate(2027, 2, 8);
const LocalDate _firstMondayAfter = LocalDate(2027, 2, 15);

ReviewInputs _inputs({
  bool maintenance = false,
  int week = 12,
  bool pregnant = false,
  LossRate? rate = _onTrack,
  double? previousPercentLow,
  List<int?> readiness = const [70, 70, 70, 70, 70, 70, 70],
  bool recoveryPrevious = false,
  CheckInEnergy? energy,
  CheckInEnergy? energyPrevious,
}) => ReviewInputs(
  kind: GoalKind.loseFat,
  week: week,
  levers: _levers,
  adherencePrevious: 1,
  baseline: _baseline,
  effortRaisesInRow: 0,
  rate: rate,
  targetPercent: 0.5,
  capPercent: 0.5,
  previousPercentLow: previousPercentLow,
  bmi: 24.55,
  pregnantOrBreastfeeding: pregnant,
  screeningPositive: false,
  bodyOn: true,
  readiness: readiness,
  recoveryPrevious: recoveryPrevious,
  energy: energy,
  energyPrevious: energyPrevious,
  foodOrWeight: null,
  foodOrWeightPrevious: null,
  maintenance: maintenance,
);

void main() {
  test('the block of the fixture ends on the Monday the tests use', () {
    expect(_block().end, _end);
  });

  group('G11b1 criterion 1: a block closes by date', () {
    test('the Monday equal to block.end does not close', () {
      expect(blockCloses(block: _block(), monday: _end, trendKg: 100), isFalse);
    });

    test('the Monday after block.end closes', () {
      expect(
        blockCloses(block: _block(), monday: _firstMondayAfter, trendKg: 100),
        isTrue,
      );
    });

    test('a Monday long after block.end closes', () {
      expect(
        blockCloses(
          block: _block(),
          monday: const LocalDate(2027, 3, 22),
          trendKg: 100,
        ),
        isTrue,
      );
    });

    test('a null trend closes only by date, after the end', () {
      expect(
        blockCloses(block: _block(), monday: _firstMondayAfter, trendKg: null),
        isTrue,
      );
    });

    test('a null trend before the end does not close', () {
      expect(
        blockCloses(block: _block(), monday: _end, trendKg: null),
        isFalse,
      );
    });
  });

  group('G11b1 criterion 2: a block closes by the trend', () {
    const week9 = LocalDate(2027, 1, 18);

    test('a trend exactly 10 percent under the anchor closes', () {
      expect(blockCloses(block: _block(), monday: week9, trendKg: 90), isTrue);
    });

    test('a trend just above 10 percent under the anchor does not', () {
      expect(
        blockCloses(block: _block(), monday: week9, trendKg: 90.01),
        isFalse,
      );
    });

    test('a trend just under 10 percent under the anchor closes', () {
      expect(
        blockCloses(block: _block(), monday: week9, trendKg: 89.99),
        isTrue,
      );
    });

    test('a trend further under the anchor closes', () {
      expect(blockCloses(block: _block(), monday: week9, trendKg: 80), isTrue);
    });

    test('the anchor is the weight the block started from, not blockKg', () {
      final gentle = goalBlock(
        startKg: 100,
        percentPerWeek: 0.25,
        start: const LocalDate(2026, 11, 17),
      );

      expect(blockCloses(block: gentle, monday: week9, trendKg: 95), isFalse);
      expect(blockCloses(block: gentle, monday: week9, trendKg: 90), isTrue);
    });
  });

  group('G11b1 criterion 3: a maintenance week holds', () {
    test('the same inputs outside maintenance propose a change', () {
      final review = reviewWeek(_inputs(week: 3));

      expect(review.change, isNotNull);
    });

    test('a slow week outside maintenance steps, in maintenance it holds', () {
      const slow = LossRate(
        kg: 0.05,
        kgLow: 0.01,
        kgHigh: 0.1,
        percent: 0.06,
        percentLow: 0.01,
        percentHigh: 0.12,
      );

      final outside = reviewWeek(_inputs(rate: slow));
      final inside = reviewWeek(_inputs(rate: slow, maintenance: true));

      expect(outside.rule, ReviewRule.stepSlow);
      expect(inside.change, isNull);
      expect(inside.action, ReviewAction.hold);
    });

    test('maintenance answers hold with no change', () {
      final review = reviewWeek(_inputs(maintenance: true));

      expect(review.action, ReviewAction.hold);
      expect(review.change, isNull);
      expect(review.needsConsent, isFalse);
    });

    test('maintenance answers with the hold of any other case', () {
      final review = reviewWeek(_inputs(maintenance: true));

      expect(review.rule, ReviewRule.holdOther);
    });

    test('maintenance holds even in the build weeks', () {
      final review = reviewWeek(_inputs(maintenance: true, week: 3));

      expect(review.action, ReviewAction.hold);
      expect(review.change, isNull);
    });

    test('rule 1 still ends the goal', () {
      final review = reviewWeek(_inputs(maintenance: true, pregnant: true));

      expect(review.rule, ReviewRule.end);
      expect(review.action, ReviewAction.end);
    });

    test('rule 2 still pauses for fast loss twice', () {
      const fast = LossRate(
        kg: 0.9,
        kgLow: 0.8,
        kgHigh: 1,
        percent: 1.1,
        percentLow: 0.9,
        percentHigh: 1.3,
      );

      final review = reviewWeek(
        _inputs(maintenance: true, rate: fast, previousPercentLow: 0.9),
      );

      expect(review.rule, ReviewRule.pauseFastLoss);
      expect(review.action, ReviewAction.pause);
      expect(review.pauseDays, goalFastLossPauseDays);
    });

    test('rule 3 still pauses for a check-in twice', () {
      final review = reviewWeek(
        _inputs(
          maintenance: true,
          energy: CheckInEnergy.low,
          energyPrevious: CheckInEnergy.low,
        ),
      );

      expect(review.rule, ReviewRule.pauseCheckIn);
      expect(review.action, ReviewAction.pause);
    });

    test('rule 4 still gives a recovery week', () {
      final review = reviewWeek(
        _inputs(
          maintenance: true,
          readiness: const [52, 49, 58, 54, 61, 50, 66],
        ),
      );

      expect(review.rule, ReviewRule.recoveryWeek);
      expect(review.action, ReviewAction.recoveryWeek);
    });

    test('rule 4 after a recovery week still pauses', () {
      final review = reviewWeek(
        _inputs(
          maintenance: true,
          readiness: const [52, 49, 58, 54, 61, 50, 66],
          recoveryPrevious: true,
        ),
      );

      expect(review.action, ReviewAction.pause);
      expect(review.pauseDays, goalRecoveryPauseDays);
    });
  });
}
