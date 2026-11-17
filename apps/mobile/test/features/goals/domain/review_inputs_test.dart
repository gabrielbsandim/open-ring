import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_codec.dart';
import 'package:open_ring/features/goals/domain/review_inputs.dart';

import '../goal_fixtures.dart';

LocalDate day(int month, int day) => LocalDate(2026, month, day);

const monday = LocalDate(2026, 12, 7);
const readyRate = WeightRateReady(
  perWeek: -0.2958,
  low: -0.3881,
  high: -0.2034,
);
const fastRate = WeightRateReady(perWeek: -0.964, low: -1.082, high: -0.845);

LossRate? lossRateOf(double? percentLow) {
  if (percentLow == null) return null;
  return LossRate(
    kg: 0.3,
    kgLow: 0.2,
    kgHigh: 0.4,
    percent: 0.4,
    percentLow: percentLow,
    percentHigh: 0.5,
  );
}

ReviewInputs rowInputs({
  List<LeverWeek> levers = const [],
  double? percentLow,
  CheckInEnergy? energy,
  bool? foodOrWeight,
}) => ReviewInputs(
  kind: f1.kind,
  week: f1.week,
  levers: levers,
  adherencePrevious: f1.adherencePrevious,
  baseline: f1.baseline,
  effortRaisesInRow: f1.effortRaisesInRow,
  rate: lossRateOf(percentLow),
  targetPercent: f1.targetPercent,
  capPercent: f1.capPercent,
  previousPercentLow: f1.previousPercentLow,
  bmi: f1.bmi,
  pregnantOrBreastfeeding: false,
  screeningPositive: false,
  bodyOn: true,
  readiness: f1.readiness,
  recoveryPrevious: false,
  energy: energy,
  energyPrevious: CheckInEnergy.normal,
  foodOrWeight: foodOrWeight,
  foodOrWeightPrevious: false,
);

GoalWeek weekRow(
  LocalDate monday, {
  ReviewInputs? inputs,
  ReviewAction action = ReviewAction.hold,
  LeverChange? change,
  WeekAnswer? answer,
}) => GoalWeek(
  goalId: 1,
  monday: monday,
  inputs: inputs ?? rowInputs(),
  rule: ReviewRule.holdOther,
  action: action,
  change: change,
  answer: answer,
);

GoalWeek effortRow(
  LocalDate monday,
  int? from,
  int to, [
  WeekAnswer? answer = WeekAnswer.accepted,
]) => weekRow(
  monday,
  action: ReviewAction.nextStep,
  change: LeverChange(kind: LeverKind.effortPoints, from: from, to: to),
  answer: answer,
);

GoalWeek previousRow({
  double percentLow = 0.3,
  ReviewAction action = ReviewAction.hold,
  CheckInEnergy? energy,
  bool? foodOrWeight,
}) => weekRow(
  day(11, 30),
  action: action,
  inputs: rowInputs(
    levers: const [
      LeverWeek(lever: strengthLever, achieved: 2),
      LeverWeek(lever: sleepLever, achieved: 5),
    ],
    percentLow: percentLow,
    energy: energy,
    foodOrWeight: foodOrWeight,
  ),
);

DateTime _local(LocalDate date, int minuteOfDay) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).add(Duration(minutes: minuteOfDay));

SleepNight nightEnding(LocalDate date, {required int onset}) {
  final onsetDate = onset >= 720 ? date.addDays(-1) : date;
  return SleepNight([
    SleepSpan(
      start: _local(onsetDate, onset),
      end: _local(date, 420),
      phase: SleepPhase.light,
      utcOffset: Duration.zero,
    ),
  ]);
}

const int _lateSleeper = 23 * 60 + 30;

GoalWeekData closedWeek() => GoalWeekData(
  steps: {
    day(11, 30): 9000,
    day(12, 1): 9500,
    day(12, 2): 10000,
    day(12, 3): 9100,
    day(12, 4): 12000,
    day(12, 5): 8500,
    day(12, 6): 8999,
    day(12, 7): 20000,
  },
  nights: {
    for (var d = 1; d <= 6; d++)
      day(12, d): nightEnding(day(12, d), onset: _lateSleeper),
    day(12, 7): nightEnding(day(12, 7), onset: _lateSleeper),
  },
  strengthDays: {day(11, 30), day(12, 5)},
);

Goal goalWith({
  GoalKind kind = GoalKind.loseFat,
  GoalPace? pace = GoalPace.standard,
  List<Lever> levers = const [strengthLever, sleepLever, stepsLever],
}) => Goal(
  id: 1,
  kind: kind,
  pace: pace,
  startedOn: day(11, 16),
  anchorKg: 78,
  referenceKg: 70,
  blockStartedOn: day(11, 16),
  blockAnchorKg: 78,
  phase: GoalPhase.block,
  phaseSince: day(11, 16),
  phaseUntil: null,
  levers: levers,
  endedOn: null,
  endReason: null,
);

ReviewInputs build({
  Goal? goal,
  LocalDate? on,
  GoalWeekData? data,
  List<GoalWeek>? weeks,
  List<GoalScreening> screenings = const [],
  bool bodyOn = true,
  WeightRate? rate = readyRate,
  double? trendKg = 77.782,
  double? heightCm = 178,
  List<int?> readiness = const [76, 72, 70, 68, 74, 71, 76],
  CheckInEnergy? energy,
  bool? foodOrWeight,
}) => closedWeekInputs(
  goal: goal ?? goalWith(),
  monday: on ?? monday,
  data: data ?? closedWeek(),
  baseline: f1.baseline,
  weeks: weeks ?? [previousRow()],
  screenings: screenings,
  bodyOn: bodyOn,
  rate: rate,
  trendKg: trendKg,
  heightCm: heightCm,
  readiness: readiness,
  energy: energy,
  foodOrWeight: foodOrWeight,
);

Matcher near(double value, [double tolerance = 0.0005]) =>
    closeTo(value, tolerance);

void main() {
  group('case 7: no previous week', () {
    test('an empty history gives null, null, false, 0, null, null', () {
      final history = reviewHistory(const [], monday: monday);

      expect(history.adherencePrevious, isNull);
      expect(history.previousPercentLow, isNull);
      expect(history.recoveryPrevious, isFalse);
      expect(history.effortRaisesInRow, 0);
      expect(history.energyPrevious, isNull);
      expect(history.foodOrWeightPrevious, isNull);
    });

    test('a single row on 11-23 is a gap and gives the same', () {
      final history = reviewHistory([
        weekRow(
          day(11, 23),
          action: ReviewAction.recoveryWeek,
          inputs: rowInputs(
            levers: const [LeverWeek(lever: strengthLever, achieved: 2)],
            percentLow: 0.3,
            energy: CheckInEnergy.low,
            foodOrWeight: true,
          ),
        ),
      ], monday: monday);

      expect(history.adherencePrevious, isNull);
      expect(history.previousPercentLow, isNull);
      expect(history.recoveryPrevious, isFalse);
      expect(history.effortRaisesInRow, 0);
      expect(history.energyPrevious, isNull);
      expect(history.foodOrWeightPrevious, isNull);
    });

    test('a gap week resets the effort streak', () {
      final history = reviewHistory([
        effortRow(day(11, 16), 150, 165),
        effortRow(day(11, 23), 165, 182),
      ], monday: monday);

      expect(history.effortRaisesInRow, 0);
    });
  });

  group('case 8: the previous week', () {
    final history = reviewHistory([
      previousRow(
        action: ReviewAction.recoveryWeek,
        energy: CheckInEnergy.low,
        foodOrWeight: true,
      ),
    ], monday: monday);

    test('the adherence is that of its levers', () {
      expect(history.adherencePrevious, 1.0);
    });

    test('the percent low is that of its rate', () {
      expect(history.previousPercentLow, 0.3);
    });

    test('a recovery week action marks recovery previous', () {
      expect(history.recoveryPrevious, isTrue);
    });

    test('the check-in answers are those of its own inputs', () {
      expect(history.energyPrevious, CheckInEnergy.low);
      expect(history.foodOrWeightPrevious, isTrue);
    });

    test('no effort change gives a streak of 0', () {
      expect(history.effortRaisesInRow, 0);
    });

    test('another action is not a recovery week', () {
      final held = reviewHistory([previousRow()], monday: monday);

      expect(held.recoveryPrevious, isFalse);
    });

    test('a row without a rate gives a null percent low', () {
      final row = weekRow(day(11, 30));
      final bare = reviewHistory([row], monday: monday);

      expect(bare.previousPercentLow, isNull);
    });

    test('a row without levers gives an adherence of 0 and does not throw', () {
      final bare = reviewHistory([weekRow(day(11, 30))], monday: monday);

      expect(bare.adherencePrevious, 0);
    });
  });

  group('case 9: the effort raises in a row', () {
    final accepted = [
      effortRow(day(11, 16), 150, 165),
      effortRow(day(11, 23), 165, 182),
      effortRow(day(11, 30), 182, 200),
    ];

    test('three accepted raises count 3', () {
      expect(reviewHistory(accepted, monday: monday).effortRaisesInRow, 3);
    });

    test('a declined raise on 11-23 stops the walk at 1', () {
      final history = reviewHistory([
        accepted[0],
        effortRow(day(11, 23), 165, 182, WeekAnswer.declined),
        accepted[2],
      ], monday: monday);

      expect(history.effortRaisesInRow, 1);
    });

    test('an unanswered raise on 11-30 gives 0', () {
      final history = reviewHistory([
        accepted[0],
        accepted[1],
        effortRow(day(11, 30), 182, 200, null),
      ], monday: monday);

      expect(history.effortRaisesInRow, 0);
    });

    test('an add on 11-30 gives 0', () {
      final history = reviewHistory([
        accepted[0],
        accepted[1],
        effortRow(day(11, 30), null, 200),
      ], monday: monday);

      expect(history.effortRaisesInRow, 0);
    });

    test('a lowered target on 11-30 gives 0', () {
      final history = reviewHistory([
        accepted[0],
        accepted[1],
        effortRow(day(11, 30), 200, 190),
      ], monday: monday);

      expect(history.effortRaisesInRow, 0);
    });

    test('a change of another lever stops the walk', () {
      final history = reviewHistory([
        accepted[0],
        weekRow(
          day(11, 23),
          change: const LeverChange(
            kind: LeverKind.steps,
            from: 8000,
            to: 9000,
          ),
          answer: WeekAnswer.accepted,
        ),
        accepted[2],
      ], monday: monday);

      expect(history.effortRaisesInRow, 1);
    });

    test('a missing row on 11-23 stops the walk', () {
      final history = reviewHistory([accepted[0], accepted[2]], monday: monday);

      expect(history.effortRaisesInRow, 1);
    });

    test('the order of the rows does not matter', () {
      final history = reviewHistory(accepted.reversed.toList(), monday: monday);

      expect(history.effortRaisesInRow, 3);
    });
  });

  group('case 10: the screening flags', () {
    test('no screening gives false and false', () {
      final flags = screeningFlags(const []);

      expect(flags.pregnantOrBreastfeeding, isFalse);
      expect(flags.screeningPositive, isFalse);
    });

    test('the newest answer to each question wins, pregnancy true', () {
      final flags = screeningFlags([
        GoalScreening(
          on: day(12, 1),
          softMode: null,
          pregnantOrBreastfeeding: true,
        ),
        GoalScreening(
          on: day(11, 16),
          softMode: false,
          pregnantOrBreastfeeding: false,
        ),
      ]);

      expect(flags.pregnantOrBreastfeeding, isTrue);
      expect(flags.screeningPositive, isFalse);
    });

    test('an older positive screening is read when the newest skips it', () {
      final flags = screeningFlags([
        GoalScreening(
          on: day(12, 1),
          softMode: null,
          pregnantOrBreastfeeding: null,
        ),
        GoalScreening(
          on: day(11, 16),
          softMode: true,
          pregnantOrBreastfeeding: false,
        ),
      ]);

      expect(flags.pregnantOrBreastfeeding, isFalse);
      expect(flags.screeningPositive, isTrue);
    });

    test('a newer false is not overridden by an older true', () {
      final flags = screeningFlags([
        GoalScreening(
          on: day(12, 1),
          softMode: false,
          pregnantOrBreastfeeding: false,
        ),
        GoalScreening(
          on: day(11, 16),
          softMode: true,
          pregnantOrBreastfeeding: true,
        ),
      ]);

      expect(flags.pregnantOrBreastfeeding, isFalse);
      expect(flags.screeningPositive, isFalse);
    });
  });

  group('case 11: the weight reading of a ready rate', () {
    final reading = weightReading(
      kind: GoalKind.loseFat,
      pace: GoalPace.standard,
      bodyOn: true,
      rate: readyRate,
      trendKg: 77.782,
      heightCm: 178,
    );

    test('the loss in kilograms', () {
      expect(reading.rate?.kg, near(0.2958, 0.0001));
      expect(reading.rate?.kgLow, near(0.2034, 0.0001));
      expect(reading.rate?.kgHigh, near(0.3881, 0.0001));
    });

    test('the loss in percent of the trend', () {
      expect(reading.rate?.percent, near(0.380, 0.001));
      expect(reading.rate?.percentLow, near(0.261, 0.001));
      expect(reading.rate?.percentHigh, near(0.499, 0.001));
    });

    test('the bmi, the cap and the target', () {
      expect(reading.bmi, near(24.549));
      expect(reading.capPercent, 0.5);
      expect(reading.targetPercent, 0.5);
    });
  });

  group('case 12: the weight reading variants', () {
    WeightReading read({
      GoalKind kind = GoalKind.loseFat,
      GoalPace? pace = GoalPace.standard,
      bool bodyOn = true,
      WeightRate? rate = readyRate,
      double? trendKg = 77.782,
      double? heightCm = 178,
    }) => weightReading(
      kind: kind,
      pace: pace,
      bodyOn: bodyOn,
      rate: rate,
      trendKg: trendKg,
      heightCm: heightCm,
    );

    test('Body off gives no rate, no bmi and a cap of 0.5', () {
      final reading = read(bodyOn: false);

      expect(reading.rate, isNull);
      expect(reading.bmi, isNull);
      expect(reading.capPercent, 0.5);
    });

    test('a building rate gives no rate and keeps the bmi', () {
      final reading = read(
        rate: const WeightRateBuilding(daysMissing: 3, spanMissing: 5),
      );

      expect(reading.rate, isNull);
      expect(reading.bmi, near(24.549));
    });

    test('a missing rate gives no rate and keeps the bmi', () {
      final reading = read(rate: null);

      expect(reading.rate, isNull);
      expect(reading.bmi, near(24.549));
    });

    test('no height gives no bmi and keeps the rate', () {
      final reading = read(heightCm: null);

      expect(reading.bmi, isNull);
      expect(reading.rate, isNotNull);
      expect(reading.capPercent, 0.5);
    });

    test('a height of zero gives no bmi', () {
      expect(read(heightCm: 0).bmi, isNull);
    });

    test('no trend gives no bmi and no rate', () {
      final reading = read(trendKg: null);

      expect(reading.bmi, isNull);
      expect(reading.rate, isNull);
    });

    test('a trend of zero gives no bmi and no rate', () {
      final reading = read(trendKg: 0);

      expect(reading.bmi, isNull);
      expect(reading.rate, isNull);
    });

    test('a trend that is not finite gives no bmi', () {
      expect(read(trendKg: double.nan).bmi, isNull);
      expect(read(trendKg: double.infinity).bmi, isNull);
    });

    test('a height that is not finite gives no bmi', () {
      expect(read(heightCm: double.infinity).bmi, isNull);
    });

    test('the gentle pace gives a target of 0.25', () {
      expect(read(pace: GoalPace.gentle).targetPercent, 0.25);
    });

    test('no pace reads as the standard pace', () {
      expect(read(pace: null).targetPercent, 0.5);
    });

    test('a trend of 85.5 gives a cap of 0.75', () {
      expect(read(trendKg: 85.5).capPercent, 0.75);
    });

    test('a trend of 100 gives a cap of 1', () {
      expect(read(trendKg: 100).capPercent, 1);
    });

    test('sleepBetter gives null, 0.5, 0.5, null', () {
      final reading = read(kind: GoalKind.sleepBetter);

      expect(reading.rate, isNull);
      expect(reading.targetPercent, 0.5);
      expect(reading.capPercent, 0.5);
      expect(reading.bmi, isNull);
    });

    test('getFitter gives null, 0.5, 0.5, null even with a gentle pace', () {
      final reading = read(kind: GoalKind.getFitter, pace: GoalPace.gentle);

      expect(reading.rate, isNull);
      expect(reading.targetPercent, 0.5);
      expect(reading.capPercent, 0.5);
      expect(reading.bmi, isNull);
    });
  });

  group('case 13: the inputs of the Monday fixture', () {
    final inputs = build();

    test('the kind is the goal kind', () {
      expect(inputs.kind, GoalKind.loseFat);
    });

    test('the week is the fourth of the block', () {
      expect(inputs.week, 4);
    });

    test('the levers are in goal order with the closed week counted', () {
      expect(
        [
          for (final week in inputs.levers)
            (week.lever.kind, week.lever.target, week.achieved),
        ],
        [
          (LeverKind.strengthDays, 2, 2),
          (LeverKind.sleepWindow, 690, 6),
          (LeverKind.steps, 9000, 5),
        ],
      );
    });

    test('the previous week fills the history fields', () {
      expect(inputs.adherencePrevious, 1.0);
      expect(inputs.previousPercentLow, 0.3);
      expect(inputs.recoveryPrevious, isFalse);
      expect(inputs.effortRaisesInRow, 0);
      expect(inputs.energyPrevious, isNull);
      expect(inputs.foodOrWeightPrevious, isNull);
    });

    test('the weight fields are those of case 11', () {
      expect(inputs.rate?.kg, near(0.2958, 0.0001));
      expect(inputs.rate?.percentLow, near(0.261, 0.001));
      expect(inputs.bmi, near(24.549));
      expect(inputs.capPercent, 0.5);
      expect(inputs.targetPercent, 0.5);
    });

    test('the baseline, readiness and body flag pass through', () {
      expect(inputs.baseline.stepsMedian14, 8000);
      expect(inputs.baseline.bedMedian, 705);
      expect(inputs.baseline.wakeMedian, 405);
      expect(inputs.baseline.effortMean4Weeks, isNull);
      expect(inputs.baseline.strengthDaysUsual, 1);
      expect(inputs.readiness, [76, 72, 70, 68, 74, 71, 76]);
      expect(inputs.bodyOn, isTrue);
    });

    test('no screening gives false flags', () {
      expect(inputs.pregnantOrBreastfeeding, isFalse);
      expect(inputs.screeningPositive, isFalse);
    });

    test('the screening flags come from the stored screenings', () {
      final flagged = build(
        screenings: [
          GoalScreening(
            on: day(12, 1),
            softMode: true,
            pregnantOrBreastfeeding: true,
          ),
        ],
      );

      expect(flagged.pregnantOrBreastfeeding, isTrue);
      expect(flagged.screeningPositive, isTrue);
    });

    test('the check-in of this week passes through', () {
      final answered = build(energy: CheckInEnergy.low, foodOrWeight: true);

      expect(answered.energy, CheckInEnergy.low);
      expect(answered.foodOrWeight, isTrue);
    });

    test('the whole closed week is counted against the goal target', () {
      final raised = build(
        goal: goalWith(
          levers: const [
            strengthLever,
            sleepLever,
            Lever(kind: LeverKind.steps, target: 10000),
          ],
        ),
      );

      expect(raised.levers[2].achieved, 2);
    });

    test('a goal with no levers gives no lever weeks and does not throw', () {
      final base = build(goal: goalWith(levers: const []));

      expect(base.levers, isEmpty);
    });

    test('a rate with Body off is dropped even with a stored trend', () {
      final off = build(bodyOn: false);

      expect(off.bodyOn, isFalse);
      expect(off.rate, isNull);
      expect(off.bmi, isNull);
    });

    test('the review is rule 6 with steps from 9000 to 10000', () {
      final review = reviewWeek(inputs);

      expect(review.rule, ReviewRule.build);
      expect(review.action, ReviewAction.nextStep);
      expect(review.change?.kind, LeverKind.steps);
      expect(review.change?.from, 9000);
      expect(review.change?.to, 10000);
    });
  });

  group('case 14: a fast loss twice', () {
    final fast = build(
      rate: fastRate,
      trendKg: 76.346,
      weeks: [previousRow(percentLow: 0.56)],
    );

    test('pauses for 28 days under rule 2', () {
      final review = reviewWeek(fast);

      expect(review.rule, ReviewRule.pauseFastLoss);
      expect(review.action, ReviewAction.pause);
      expect(review.pauseDays, 28);
    });

    test('the same with Body off is not rule 2', () {
      final off = build(
        rate: fastRate,
        trendKg: 76.346,
        bodyOn: false,
        weeks: [previousRow(percentLow: 0.56)],
      );

      expect(reviewWeek(off).rule, isNot(ReviewRule.pauseFastLoss));
    });
  });

  group('case 15: low readiness', () {
    const low = [52, 49, 58, 54, 61, 50, 66];

    test('four low days give a recovery week', () {
      final review = reviewWeek(build(readiness: low));

      expect(review.rule, ReviewRule.recoveryWeek);
      expect(review.action, ReviewAction.recoveryWeek);
    });

    test('six readiness values throw an ArgumentError', () {
      expect(() => build(readiness: low.sublist(0, 6)), throwsArgumentError);
    });

    test('eight readiness values throw an ArgumentError', () {
      expect(() => build(readiness: [...low, 70]), throwsArgumentError);
    });

    test('a Tuesday monday throws an ArgumentError', () {
      expect(() => build(on: day(12, 8), readiness: low), throwsArgumentError);
    });
  });

  group('case 16: the codec', () {
    test('encoding the fixture inputs and decoding gives the same inputs', () {
      final inputs = build();

      final decoded = decodeReviewInputs(encodeReviewInputs(inputs));

      expect(decoded, isNotNull);
      expectSameInputs(decoded!, inputs);
    });
  });

  group('case 1 of G5b2a: the weight snapshot of a 28 day line', () {
    final daily = [
      for (var i = 0; i < 28; i++)
        (date: day(11, 9).addDays(i), value: 80.0 - 0.05 * i),
    ];
    final snapshot = weightSnapshot(daily: daily, asOf: day(12, 6));

    test('the rate is ready', () {
      expect(snapshot.rate, isA<WeightRateReady>());
    });

    test('the rate per week, low and high are -0.35', () {
      final rate = snapshot.rate! as WeightRateReady;

      expect(rate.perWeek, closeTo(-0.35, 1e-6));
      expect(rate.low, closeTo(-0.35, 1e-6));
      expect(rate.high, closeTo(-0.35, 1e-6));
    });

    test('the trend is the trend of the weigh-ins up to the day', () {
      expect(snapshot.trendKg, closeTo(79.06511, 1e-4));
    });

    test('a point after the day changes neither the rate nor the trend', () {
      final later = weightSnapshot(
        daily: [...daily, (date: day(12, 7), value: 70.0)],
        asOf: day(12, 6),
      );
      final rate = later.rate! as WeightRateReady;

      expect(rate.perWeek, closeTo(-0.35, 1e-6));
      expect(rate.low, closeTo(-0.35, 1e-6));
      expect(rate.high, closeTo(-0.35, 1e-6));
      expect(later.trendKg, snapshot.trendKg);
    });

    test('a later weigh-in does not move a trend still being seeded', () {
      final later = weightSnapshot(
        daily: [
          for (final d in [30, 32, 34, 36])
            (date: day(11, 30).addDays(d - 30), value: 80.0),
          (date: day(12, 7), value: 70.0),
        ],
        asOf: day(12, 6),
      );

      expect(later.trendKg, 80.0);
    });
  });

  group('case 2 of G5b2a: the age of the trend and empty lists', () {
    test('a trend 27 days old is kept', () {
      final snapshot = weightSnapshot(
        daily: [(date: day(11, 9), value: 79.5)],
        asOf: day(12, 6),
      );

      expect(snapshot.trendKg, 79.5);
    });

    test('a trend 28 days old is null', () {
      final snapshot = weightSnapshot(
        daily: [(date: day(11, 8), value: 79.5)],
        asOf: day(12, 6),
      );

      expect(snapshot.trendKg, isNull);
    });

    test('an empty list gives a null rate and a null trend', () {
      final snapshot = weightSnapshot(daily: const [], asOf: day(12, 6));

      expect(snapshot.rate, isNull);
      expect(snapshot.trendKg, isNull);
    });

    test('only weigh-ins after the day give a null rate and trend', () {
      final snapshot = weightSnapshot(
        daily: [(date: day(12, 7), value: 70.0)],
        asOf: day(12, 6),
      );

      expect(snapshot.rate, isNull);
      expect(snapshot.trendKg, isNull);
    });
  });

  group('case 3 of G5b2a: withCheckIn', () {
    test('replaces the energy and the food or weight answer', () {
      final next = withCheckIn(
        f1,
        energy: CheckInEnergy.low,
        foodOrWeight: null,
      );

      expectSameInputs(
        next,
        f1With(
          energy: CheckInEnergy.low,
          energyPrevious: f1.energyPrevious,
          foodOrWeight: null,
        ),
      );
    });

    test('sets both answers when both are given', () {
      final next = withCheckIn(
        f0,
        energy: CheckInEnergy.good,
        foodOrWeight: true,
      );

      expect(next.energy, CheckInEnergy.good);
      expect(next.foodOrWeight, isTrue);
    });

    test('leaves the input untouched', () {
      withCheckIn(f1, energy: CheckInEnergy.low, foodOrWeight: true);

      expect(f1.energy, CheckInEnergy.good);
      expect(f1.foodOrWeight, isFalse);
    });
  });
}
