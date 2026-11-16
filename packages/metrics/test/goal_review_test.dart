import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const tight = 1e-9;

const LossRate onTrackRate = LossRate(
  kg: 0.2958,
  kgLow: 0.2034,
  kgHigh: 0.3881,
  percent: 0.380,
  percentLow: 0.261,
  percentHigh: 0.499,
);

const List<int?> restedWeek = [70, 70, 70, 70, 70, 70, 70];

LossRate fromPercents(double low, double high) => LossRate(
  kg: (low + high) / 2,
  kgLow: low,
  kgHigh: high,
  percent: (low + high) / 2,
  percentLow: low,
  percentHigh: high,
);

LeverBaseline baselineOf({
  int? steps = 8000,
  int? bed = 705,
  int? wake = 405,
  double? effort = 150,
  int usual = 1,
}) => LeverBaseline(
  stepsMedian14: steps,
  bedMedian: bed,
  wakeMedian: wake,
  effortMean4Weeks: effort,
  strengthDaysUsual: usual,
);

LeverWeek weekOf(LeverKind kind, int target, int achieved) => LeverWeek(
  lever: Lever(kind: kind, target: target),
  achieved: achieved,
);

LeverWeek strengthWeek(int target, int achieved) =>
    weekOf(LeverKind.strengthDays, target, achieved);

LeverWeek sleepWeek(int target, int achieved) =>
    weekOf(LeverKind.sleepWindow, target, achieved);

LeverWeek stepsWeek(int target, int achieved) =>
    weekOf(LeverKind.steps, target, achieved);

LeverWeek effortWeek(int target, int achieved) =>
    weekOf(LeverKind.effortPoints, target, achieved);

LeverWeek wakeWeek(int target, int achieved) =>
    weekOf(LeverKind.wakeTime, target, achieved);

final List<LeverWeek> caseOneLevers = [
  strengthWeek(2, 2),
  sleepWeek(690, 6),
  stepsWeek(9000, 5),
];

final List<LeverWeek> ceilingLevers = [
  strengthWeek(4, 4),
  sleepWeek(585, 6),
  stepsWeek(10000, 5),
];

List<LeverWeek> fitterLevers({
  int effortTarget = 150,
  int effortDone = 160,
  int stepsTarget = 9000,
  int stepsDone = 5,
  int strengthTarget = 2,
  int strengthDone = 2,
}) => [
  effortWeek(effortTarget, effortDone),
  stepsWeek(stepsTarget, stepsDone),
  strengthWeek(strengthTarget, strengthDone),
];

Review reviewOf({
  GoalKind kind = GoalKind.loseFat,
  int week = 4,
  List<LeverWeek>? levers,
  double? adherencePrevious,
  LeverBaseline? base,
  int effortRaisesInRow = 0,
  LossRate? rate = onTrackRate,
  double targetPercent = 0.5,
  double capPercent = 0.5,
  double? previousPercentLow,
  double? bmiValue = 24.55,
  bool pregnant = false,
  bool screening = false,
  bool bodyOn = true,
  List<int?> readiness = restedWeek,
  bool recoveryPrevious = false,
  CheckInEnergy? energy,
  CheckInEnergy? energyPrevious,
  bool? foodOrWeight,
  bool? foodOrWeightPrevious,
}) => reviewWeek(
  ReviewInputs(
    kind: kind,
    week: week,
    levers: levers ?? caseOneLevers,
    adherencePrevious: adherencePrevious,
    baseline: base ?? baselineOf(),
    effortRaisesInRow: effortRaisesInRow,
    rate: rate,
    targetPercent: targetPercent,
    capPercent: capPercent,
    previousPercentLow: previousPercentLow,
    bmi: bmiValue,
    pregnantOrBreastfeeding: pregnant,
    screeningPositive: screening,
    bodyOn: bodyOn,
    readiness: readiness,
    recoveryPrevious: recoveryPrevious,
    energy: energy,
    energyPrevious: energyPrevious,
    foodOrWeight: foodOrWeight,
    foodOrWeightPrevious: foodOrWeightPrevious,
  ),
);

LeverChange? step({
  GoalKind kind = GoalKind.loseFat,
  List<LeverWeek>? levers,
  LeverBaseline? base,
  double? previous,
  int raises = 0,
}) => nextStep(
  kind: kind,
  levers: levers ?? caseOneLevers,
  baseline: base ?? baselineOf(),
  adherencePrevious: previous,
  effortRaisesInRow: raises,
);

void expectChange(LeverChange? change, LeverKind kind, int? from, int? to) {
  expect(change, isNotNull);
  expect(change!.kind, kind);
  expect(change.from, from);
  expect(change.to, to);
}

List<LeverKind> kindsOf(List<Lever> levers) => [
  for (final lever in levers) lever.kind,
];

void main() {
  group('leverFits', () {
    test('a daily lever fits from five days of seven', () {
      expect(leverFits(sleepWeek(690, 5)), isTrue);
      expect(leverFits(sleepWeek(690, 4)), isFalse);
      expect(leverFits(stepsWeek(9000, 5)), isTrue);
      expect(leverFits(stepsWeek(9000, 4)), isFalse);
      expect(leverFits(wakeWeek(405, 5)), isTrue);
      expect(leverFits(wakeWeek(405, 4)), isFalse);
    });

    test('a daily lever ignores its target', () {
      expect(leverFits(stepsWeek(20000, 5)), isTrue);
      expect(leverFits(sleepWeek(1, 7)), isTrue);
    });

    test('a weekly lever fits at its target and not one below', () {
      expect(leverFits(strengthWeek(2, 2)), isTrue);
      expect(leverFits(strengthWeek(2, 1)), isFalse);
      expect(leverFits(strengthWeek(2, 3)), isTrue);
      expect(leverFits(effortWeek(150, 150)), isTrue);
      expect(leverFits(effortWeek(150, 149)), isFalse);
    });
  });

  group('leverFitRatio', () {
    test('a daily lever is its days over seven, with no cap at five', () {
      expect(leverFitRatio(sleepWeek(690, 5)), closeTo(5 / 7, tight));
      expect(leverFitRatio(stepsWeek(9000, 3)), closeTo(3 / 7, tight));
      expect(leverFitRatio(wakeWeek(405, 7)), closeTo(1, tight));
      expect(leverFitRatio(stepsWeek(9000, 0)), 0);
    });

    test('a weekly lever is achieved over target, capped at one', () {
      expect(leverFitRatio(strengthWeek(2, 1)), closeTo(0.5, tight));
      expect(leverFitRatio(strengthWeek(2, 3)), closeTo(1, tight));
      expect(leverFitRatio(effortWeek(150, 100)), closeTo(100 / 150, tight));
      expect(leverFitRatio(effortWeek(150, 400)), closeTo(1, tight));
    });
  });

  group('adherence', () {
    test('no levers is zero', () {
      expect(adherence(const []), 0);
    });

    test('it is the levers that fit over the active ones', () {
      expect(adherence(caseOneLevers), closeTo(1, tight));
      expect(
        adherence([strengthWeek(2, 1), sleepWeek(690, 3), stepsWeek(9000, 5)]),
        closeTo(1 / 3, tight),
      );
      expect(
        adherence([strengthWeek(2, 2), sleepWeek(690, 6), stepsWeek(9000, 3)]),
        closeTo(2 / 3, tight),
      );
    });

    test('three fits of five is exactly 0.6 and four of five is 0.8', () {
      final threeOfFive = [
        strengthWeek(2, 2),
        sleepWeek(690, 5),
        stepsWeek(9000, 5),
        effortWeek(150, 100),
        wakeWeek(405, 2),
      ];
      final fourOfFive = [
        strengthWeek(2, 2),
        sleepWeek(690, 5),
        stepsWeek(9000, 5),
        effortWeek(150, 150),
        wakeWeek(405, 2),
      ];
      expect(adherence(threeOfFive), 0.6);
      expect(adherence(fourOfFive), 0.8);
    });
  });

  group('Lever unit and cadence', () {
    test('every kind has its unit', () {
      final units = {
        LeverKind.strengthDays: LeverUnit.daysPerWeek,
        LeverKind.sleepWindow: LeverUnit.minutesAfterNoon,
        LeverKind.steps: LeverUnit.stepsPerDay,
        LeverKind.effortPoints: LeverUnit.pointsPerWeek,
        LeverKind.wakeTime: LeverUnit.minutesAfterMidnight,
      };
      for (final entry in units.entries) {
        expect(Lever(kind: entry.key, target: 1).unit, entry.value);
      }
    });

    test('sleep window, steps and wake time are daily, the rest weekly', () {
      final cadences = {
        LeverKind.strengthDays: LeverCadence.weekly,
        LeverKind.sleepWindow: LeverCadence.daily,
        LeverKind.steps: LeverCadence.daily,
        LeverKind.effortPoints: LeverCadence.weekly,
        LeverKind.wakeTime: LeverCadence.daily,
      };
      for (final entry in cadences.entries) {
        expect(Lever(kind: entry.key, target: 1).cadence, entry.value);
      }
    });
  });

  group('goalLeverOrder', () {
    test('lose fat adds strength, then sleep, then steps', () {
      expect(goalLeverOrder(GoalKind.loseFat), [
        LeverKind.strengthDays,
        LeverKind.sleepWindow,
        LeverKind.steps,
      ]);
    });

    test('get fitter adds effort, then steps, then strength', () {
      expect(goalLeverOrder(GoalKind.getFitter), [
        LeverKind.effortPoints,
        LeverKind.steps,
        LeverKind.strengthDays,
      ]);
    });

    test('sleep better adds the wake time, then the sleep window', () {
      expect(goalLeverOrder(GoalKind.sleepBetter), [
        LeverKind.wakeTime,
        LeverKind.sleepWindow,
      ]);
    });
  });

  group('leverEntry steps', () {
    Lever? stepsFor(int? median, [GoalKind goal = GoalKind.loseFat]) =>
        leverEntry(LeverKind.steps, goal, baselineOf(steps: median));

    test('a median of 8,000 enters at 9,000', () {
      final lever = stepsFor(8000)!;
      expect(lever.kind, LeverKind.steps);
      expect(lever.target, 9000);
    });

    test('8,240 rounds down to 8,000 and enters at 9,000', () {
      expect(stepsFor(8240)!.target, 9000);
    });

    test('8,250 rounds up to 8,500 and enters at 9,500', () {
      expect(stepsFor(8250)!.target, 9500);
    });

    test('a median of 10,000 or more enters at 10,000', () {
      expect(stepsFor(10000)!.target, 10000);
      expect(stepsFor(12000)!.target, 10000);
      expect(stepsFor(9600)!.target, 10000);
    });

    test('a missing median has no entry', () {
      expect(stepsFor(null), isNull);
    });

    test('the goal does not change the entry', () {
      expect(stepsFor(8000, GoalKind.getFitter)!.target, 9000);
    });
  });

  group('leverEntry sleepWindow', () {
    Lever? sleepFor({int? bed = 705, int? wake = 405, GoalKind? goal}) =>
        leverEntry(
          LeverKind.sleepWindow,
          goal ?? GoalKind.loseFat,
          baselineOf(bed: bed, wake: wake),
        );

    test('a bed median of 705 enters at 690', () {
      final lever = sleepFor()!;
      expect(lever.kind, LeverKind.sleepWindow);
      expect(lever.target, 690);
    });

    test('a bed median of 800 enters at 705, seven hours before the wake', () {
      expect(sleepFor(bed: 800)!.target, 705);
    });

    test('every goal enters at the median minus 15', () {
      expect(sleepFor(goal: GoalKind.getFitter)!.target, 690);
      expect(sleepFor(goal: GoalKind.sleepBetter)!.target, 690);
    });

    test('a bed after midnight orders after one before it', () {
      final late = sleepFor(bed: 735, wake: 480)!;
      final early = sleepFor(bed: 690, wake: 480)!;
      expect(late.target, 720);
      expect(early.target, 675);
      expect(late.target, greaterThan(early.target));
    });

    test('a missing bed or wake median has no entry', () {
      expect(sleepFor(bed: null), isNull);
      expect(sleepFor(wake: null), isNull);
    });
  });

  group('leverEntry strengthDays', () {
    int strengthFor(int usual, GoalKind goal) => leverEntry(
      LeverKind.strengthDays,
      goal,
      baselineOf(usual: usual),
    )!.target;

    test('usual 0 gives 2 under lose fat and 1 under get fitter', () {
      expect(strengthFor(0, GoalKind.loseFat), 2);
      expect(strengthFor(0, GoalKind.getFitter), 1);
    });

    test('usual 1 gives 2 under both', () {
      expect(strengthFor(1, GoalKind.loseFat), 2);
      expect(strengthFor(1, GoalKind.getFitter), 2);
    });

    test('usual 3 or 4 gives 4', () {
      expect(strengthFor(3, GoalKind.loseFat), 4);
      expect(strengthFor(4, GoalKind.loseFat), 4);
      expect(strengthFor(3, GoalKind.getFitter), 4);
      expect(strengthFor(4, GoalKind.getFitter), 4);
    });
  });

  group('leverEntry effortPoints', () {
    Lever? effortFor(double? mean) => leverEntry(
      LeverKind.effortPoints,
      GoalKind.getFitter,
      baselineOf(effort: mean),
    );

    test('the entry is the mean rounded', () {
      expect(effortFor(150)!.kind, LeverKind.effortPoints);
      expect(effortFor(150)!.target, 150);
      expect(effortFor(149.6)!.target, 150);
      expect(effortFor(149.4)!.target, 149);
    });

    test('a mean over 300 enters at 300', () {
      expect(effortFor(400)!.target, 300);
      expect(effortFor(300)!.target, 300);
    });

    test('a missing mean has no entry', () {
      expect(effortFor(null), isNull);
    });
  });

  group('leverEntry wakeTime', () {
    test('the entry is the wake median', () {
      final lever = leverEntry(
        LeverKind.wakeTime,
        GoalKind.sleepBetter,
        baselineOf(),
      )!;
      expect(lever.kind, LeverKind.wakeTime);
      expect(lever.target, 405);
    });

    test('a missing wake median has no entry', () {
      expect(
        leverEntry(
          LeverKind.wakeTime,
          GoalKind.sleepBetter,
          baselineOf(wake: null),
        ),
        isNull,
      );
    });
  });

  group('startingLever', () {
    test('lose fat starts with strength days', () {
      final lever = startingLever(GoalKind.loseFat, baselineOf())!;
      expect(lever.kind, LeverKind.strengthDays);
      expect(lever.target, 2);
    });

    test('get fitter starts with effort points', () {
      final lever = startingLever(GoalKind.getFitter, baselineOf())!;
      expect(lever.kind, LeverKind.effortPoints);
      expect(lever.target, 150);
    });

    test('sleep better starts with the wake time', () {
      final lever = startingLever(GoalKind.sleepBetter, baselineOf())!;
      expect(lever.kind, LeverKind.wakeTime);
      expect(lever.target, 405);
    });
  });

  group('nextStep adds', () {
    test('with two levers it adds steps at 9,000 under lose fat', () {
      final change = step(levers: [strengthWeek(2, 2), sleepWeek(690, 6)]);
      expectChange(change, LeverKind.steps, null, 9000);
    });

    test('with only strength it adds the sleep window at 690', () {
      expectChange(
        step(levers: [strengthWeek(2, 2)]),
        LeverKind.sleepWindow,
        null,
        690,
      );
    });

    test('it adds even when the active levers did not fit', () {
      final change = step(levers: [strengthWeek(2, 0)]);
      expectChange(change, LeverKind.sleepWindow, null, 690);
    });

    test('it skips a kind with no entry and takes the next one', () {
      final change = step(
        levers: [strengthWeek(2, 2)],
        base: baselineOf(bed: null),
      );
      expectChange(change, LeverKind.steps, null, 9000);
    });

    test('sleep better adds the sleep window after the wake time', () {
      final change = step(
        kind: GoalKind.sleepBetter,
        levers: [wakeWeek(405, 5)],
      );
      expectChange(change, LeverKind.sleepWindow, null, 690);
    });

    test('get fitter adds effort, then steps, then strength', () {
      expectChange(
        step(kind: GoalKind.getFitter, levers: [effortWeek(150, 150)]),
        LeverKind.steps,
        null,
        9000,
      );
      expectChange(
        step(
          kind: GoalKind.getFitter,
          levers: [effortWeek(150, 150), stepsWeek(9000, 5)],
        ),
        LeverKind.strengthDays,
        null,
        2,
      );
    });
  });

  group('nextStep raises steps', () {
    test('9,000 rises to 10,000', () {
      expectChange(step(), LeverKind.steps, 9000, 10000);
    });

    test('9,500 rises to 10,000 and not 10,500', () {
      final levers = [
        strengthWeek(2, 2),
        sleepWeek(690, 6),
        stepsWeek(9500, 5),
      ];
      expectChange(step(levers: levers), LeverKind.steps, 9500, 10000);
    });

    test('10,000 is not raised, the next lever is', () {
      final levers = [
        strengthWeek(2, 2),
        sleepWeek(690, 6),
        stepsWeek(10000, 5),
      ];
      expectChange(step(levers: levers), LeverKind.sleepWindow, 690, 675);
    });

    test('steps that did not fit are not raised', () {
      final levers = [
        strengthWeek(2, 2),
        sleepWeek(690, 6),
        stepsWeek(9000, 4),
      ];
      expectChange(step(levers: levers), LeverKind.sleepWindow, 690, 675);
    });
  });

  group('nextStep raises the sleep window', () {
    test('690 rises to 675 with 7 hours and a half in bed', () {
      final levers = [
        strengthWeek(2, 2),
        sleepWeek(690, 6),
        stepsWeek(10000, 5),
      ];
      expectChange(step(levers: levers), LeverKind.sleepWindow, 690, 675);
    });

    test('585 is not raised, it already gives 9 hours in bed', () {
      expect(step(levers: ceilingLevers), isNull);
    });

    test('600 rises to 585, exactly 9 hours in bed', () {
      final levers = [
        strengthWeek(4, 4),
        sleepWeek(600, 6),
        stepsWeek(10000, 5),
      ];
      final change = step(levers: levers);
      expect(change?.kind, LeverKind.sleepWindow);
      expect(change?.from, 600);
      expect(change?.to, 585);
    });

    test('585 rises to 570 when the wake is earlier', () {
      final levers = [
        strengthWeek(4, 4),
        sleepWeek(585, 6),
        stepsWeek(10000, 5),
      ];
      final change = step(levers: levers, base: baselineOf(wake: 360));
      expect(change?.kind, LeverKind.sleepWindow);
      expect(change?.from, 585);
      expect(change?.to, 570);
    });
  });

  group('nextStep raises strength days', () {
    test('3 rises to 4', () {
      final levers = [
        strengthWeek(3, 3),
        sleepWeek(585, 6),
        stepsWeek(10000, 5),
      ];
      expectChange(step(levers: levers), LeverKind.strengthDays, 3, 4);
    });

    test('4 is not raised', () {
      expect(step(levers: ceilingLevers), isNull);
    });

    test('2 rises to 3 once steps and sleep are at their ceilings', () {
      final levers = [
        strengthWeek(2, 2),
        sleepWeek(585, 6),
        stepsWeek(10000, 5),
      ];
      expectChange(step(levers: levers), LeverKind.strengthDays, 2, 3);
    });
  });

  group('nextStep raises effort points', () {
    const raises = {150: 165, 100: 115, 200: 220, 290: 300};

    for (final entry in raises.entries) {
      test('${entry.key} rises to ${entry.value}', () {
        final change = step(
          kind: GoalKind.getFitter,
          levers: fitterLevers(effortTarget: entry.key, effortDone: entry.key),
          previous: 1.0,
        );
        expectChange(change, LeverKind.effortPoints, entry.key, entry.value);
      });
    }

    test('300 is not raised and the next lever is', () {
      final change = step(
        kind: GoalKind.getFitter,
        levers: fitterLevers(effortTarget: 300, effortDone: 300),
        previous: 1.0,
      );
      expectChange(change, LeverKind.steps, 9000, 10000);
    });

    test('300 with every lever at its ceiling gives no step', () {
      final change = step(
        kind: GoalKind.getFitter,
        levers: fitterLevers(
          effortTarget: 300,
          effortDone: 300,
          stepsTarget: 10000,
          strengthTarget: 4,
          strengthDone: 4,
        ),
        previous: 1.0,
      );
      expect(change, isNull);
    });

    test('three raises in a row skip effort and raise steps', () {
      final change = step(
        kind: GoalKind.getFitter,
        levers: fitterLevers(),
        previous: 1.0,
        raises: 3,
      );
      expectChange(change, LeverKind.steps, 9000, 10000);
    });

    test('two raises in a row still raise effort', () {
      final change = step(
        kind: GoalKind.getFitter,
        levers: fitterLevers(),
        previous: 1.0,
        raises: 2,
      );
      expectChange(change, LeverKind.effortPoints, 150, 165);
    });

    test('a previous adherence of exactly 0.8 raises effort', () {
      final change = step(
        kind: GoalKind.getFitter,
        levers: fitterLevers(),
        previous: 0.8,
      );
      expectChange(change, LeverKind.effortPoints, 150, 165);
    });

    test('a previous adherence under 0.8 skips effort', () {
      final change = step(
        kind: GoalKind.getFitter,
        levers: fitterLevers(),
        previous: 0.79,
      );
      expectChange(change, LeverKind.steps, 9000, 10000);
    });

    test('no previous adherence skips effort', () {
      final change = step(kind: GoalKind.getFitter, levers: fitterLevers());
      expectChange(change, LeverKind.steps, 9000, 10000);
    });

    test('effort that did not fit is not raised', () {
      final change = step(
        kind: GoalKind.getFitter,
        levers: fitterLevers(effortDone: 140),
        previous: 1.0,
      );
      expectChange(change, LeverKind.steps, 9000, 10000);
    });
  });

  group('nextStep for sleep better', () {
    test('the sleep window rises from 690 to 675', () {
      final change = step(
        kind: GoalKind.sleepBetter,
        levers: [wakeWeek(405, 6), sleepWeek(690, 5)],
      );
      expectChange(change, LeverKind.sleepWindow, 690, 675);
    });

    test('the sleep window at 585 is not raised', () {
      final change = step(
        kind: GoalKind.sleepBetter,
        levers: [wakeWeek(405, 6), sleepWeek(585, 5)],
      );
      expect(change, isNull);
    });

    test('the wake time never moves', () {
      final change = step(
        kind: GoalKind.sleepBetter,
        levers: [wakeWeek(405, 7), sleepWeek(690, 4)],
      );
      expect(change, isNull);
    });
  });

  group('shrink', () {
    test('strength 1 of 2, sleep 3 and steps 5 keep steps and strength', () {
      final kept = shrink([
        strengthWeek(2, 1),
        sleepWeek(690, 3),
        stepsWeek(9000, 5),
      ], GoalKind.loseFat);
      expect(
        kindsOf(kept),
        unorderedEquals([LeverKind.steps, LeverKind.strengthDays]),
      );
    });

    test('the kept levers keep their targets', () {
      final kept = shrink([
        strengthWeek(2, 1),
        sleepWeek(690, 3),
        stepsWeek(9000, 5),
      ], GoalKind.loseFat);
      final byKind = {for (final lever in kept) lever.kind: lever.target};
      expect(byKind[LeverKind.steps], 9000);
      expect(byKind[LeverKind.strengthDays], 2);
    });

    test('strength 0 of 2, sleep 4 and steps 3 keep strength and sleep', () {
      final kept = shrink([
        strengthWeek(2, 0),
        sleepWeek(690, 4),
        stepsWeek(9000, 3),
      ], GoalKind.loseFat);
      expect(
        kindsOf(kept),
        unorderedEquals([LeverKind.strengthDays, LeverKind.sleepWindow]),
      );
    });

    test('under lose fat strength stays whatever the other ratios are', () {
      final layouts = [
        [strengthWeek(2, 0), sleepWeek(690, 7), stepsWeek(9000, 7)],
        [strengthWeek(2, 0), sleepWeek(690, 0), stepsWeek(9000, 0)],
        [strengthWeek(2, 1), sleepWeek(690, 7), stepsWeek(9000, 6)],
        [strengthWeek(4, 0), sleepWeek(690, 1), stepsWeek(9000, 2)],
      ];
      for (final levers in layouts) {
        final kept = shrink(levers, GoalKind.loseFat);
        expect(kept, hasLength(2));
        expect(kindsOf(kept), contains(LeverKind.strengthDays));
      }
    });

    test('under lose fat a tie for the other lever follows the goal order', () {
      final kept = shrink([
        strengthWeek(2, 0),
        sleepWeek(690, 0),
        stepsWeek(9000, 0),
      ], GoalKind.loseFat);
      expect(
        kindsOf(kept),
        unorderedEquals([LeverKind.strengthDays, LeverKind.sleepWindow]),
      );
    });

    test('get fitter keeps the two highest ratios', () {
      final kept = shrink([
        effortWeek(150, 100),
        stepsWeek(9000, 5),
        strengthWeek(2, 1),
      ], GoalKind.getFitter);
      expect(
        kindsOf(kept),
        unorderedEquals([LeverKind.effortPoints, LeverKind.steps]),
      );
    });

    test('get fitter does not protect strength', () {
      final kept = shrink([
        effortWeek(150, 150),
        stepsWeek(9000, 6),
        strengthWeek(2, 0),
      ], GoalKind.getFitter);
      expect(
        kindsOf(kept),
        unorderedEquals([LeverKind.effortPoints, LeverKind.steps]),
      );
    });

    test('get fitter ties follow the goal order', () {
      final kept = shrink([
        effortWeek(150, 0),
        stepsWeek(9000, 0),
        strengthWeek(2, 0),
      ], GoalKind.getFitter);
      expect(
        kindsOf(kept),
        unorderedEquals([LeverKind.effortPoints, LeverKind.steps]),
      );
    });
  });

  group('reviewWeek rule 1 end', () {
    test('a bmi of 18.4 ends the goal with no consent', () {
      final review = reviewOf(bmiValue: 18.4);
      expect(review.rule, ReviewRule.end);
      expect(review.action, ReviewAction.end);
      expect(review.change, isNull);
      expect(review.needsConsent, isFalse);
    });

    test('a bmi of exactly 18.5 does not end it', () {
      expect(reviewOf(bmiValue: 18.5).rule, ReviewRule.build);
    });

    test('a missing bmi does not end it', () {
      expect(reviewOf(bmiValue: null).rule, ReviewRule.build);
    });

    test('pregnancy or breastfeeding ends it', () {
      final review = reviewOf(pregnant: true);
      expect(review.rule, ReviewRule.end);
      expect(review.action, ReviewAction.end);
    });

    test('a positive screening ends it', () {
      final review = reviewOf(screening: true);
      expect(review.rule, ReviewRule.end);
      expect(review.action, ReviewAction.end);
    });

    test('it only applies to lose fat', () {
      final low = reviewOf(
        kind: GoalKind.getFitter,
        levers: fitterLevers(),
        bmiValue: 18.0,
      );
      expect(low.rule, isNot(ReviewRule.end));
      final pregnant = reviewOf(
        kind: GoalKind.getFitter,
        levers: fitterLevers(),
        pregnant: true,
      );
      expect(pregnant.rule, isNot(ReviewRule.end));
      final screened = reviewOf(
        kind: GoalKind.sleepBetter,
        levers: [wakeWeek(405, 6), sleepWeek(690, 5)],
        screening: true,
      );
      expect(screened.rule, isNot(ReviewRule.end));
    });
  });

  group('reviewWeek rule 2 pauseFastLoss', () {
    final fast = fromPercents(1.11, 1.5);

    test('a low end of 1.11 with a previous 0.56 pauses 28 days', () {
      final review = reviewOf(rate: fast, previousPercentLow: 0.56);
      expect(review.rule, ReviewRule.pauseFastLoss);
      expect(review.action, ReviewAction.pause);
      expect(review.pauseDays, 28);
      expect(review.change, isNull);
      expect(review.needsConsent, isFalse);
    });

    test('a previous low end of exactly the cap eases instead', () {
      final review = reviewOf(rate: fast, previousPercentLow: 0.50);
      expect(review.rule, ReviewRule.ease);
      expect(review.action, ReviewAction.ease);
      expect(review.change, isNull);
    });

    test('a missing previous low end eases instead', () {
      expect(reviewOf(rate: fast).rule, ReviewRule.ease);
    });

    test('a low end of exactly the cap is not rule 2', () {
      final review = reviewOf(
        rate: fromPercents(0.5, 0.7),
        previousPercentLow: 0.56,
      );
      expect(review.rule, isNot(ReviewRule.pauseFastLoss));
      expect(review.rule, ReviewRule.build);
    });

    test('the previous low end is not read outside lose fat', () {
      final review = reviewOf(
        kind: GoalKind.getFitter,
        levers: fitterLevers(),
        rate: fast,
        previousPercentLow: 0.56,
      );
      expect(review.rule, isNot(ReviewRule.pauseFastLoss));
    });

    test('with the body off it still pauses', () {
      final review = reviewOf(
        rate: fast,
        previousPercentLow: 0.56,
        bodyOn: false,
      );
      expect(review.rule, ReviewRule.pauseFastLoss);
    });
  });

  group('reviewWeek rule 3 pauseCheckIn', () {
    test('food or weight yes twice pauses with no length', () {
      final review = reviewOf(foodOrWeight: true, foodOrWeightPrevious: true);
      expect(review.rule, ReviewRule.pauseCheckIn);
      expect(review.action, ReviewAction.pause);
      expect(review.pauseDays, isNull);
      expect(review.change, isNull);
      expect(review.needsConsent, isFalse);
    });

    test('food or weight yes once does not pause', () {
      expect(
        reviewOf(foodOrWeight: true, foodOrWeightPrevious: false).rule,
        ReviewRule.build,
      );
      expect(
        reviewOf(foodOrWeight: false, foodOrWeightPrevious: true).rule,
        ReviewRule.build,
      );
      expect(reviewOf(foodOrWeight: true).rule, ReviewRule.build);
      expect(reviewOf(foodOrWeightPrevious: true).rule, ReviewRule.build);
    });

    test('energy low twice pauses', () {
      final review = reviewOf(
        energy: CheckInEnergy.low,
        energyPrevious: CheckInEnergy.low,
      );
      expect(review.rule, ReviewRule.pauseCheckIn);
      expect(review.action, ReviewAction.pause);
      expect(review.pauseDays, isNull);
    });

    test('energy low once or never does not pause', () {
      expect(
        reviewOf(
          energy: CheckInEnergy.low,
          energyPrevious: CheckInEnergy.normal,
        ).rule,
        ReviewRule.build,
      );
      expect(
        reviewOf(
          energy: CheckInEnergy.good,
          energyPrevious: CheckInEnergy.low,
        ).rule,
        ReviewRule.build,
      );
      expect(reviewOf(energy: CheckInEnergy.low).rule, ReviewRule.build);
    });

    test('missing answers are neutral', () {
      final review = reviewOf(
        energy: null,
        energyPrevious: null,
        foodOrWeight: null,
        foodOrWeightPrevious: null,
      );
      expect(review.rule, ReviewRule.build);
    });

    test('a food yes and an energy low across weeks do not combine', () {
      final review = reviewOf(
        foodOrWeight: true,
        foodOrWeightPrevious: false,
        energy: CheckInEnergy.low,
        energyPrevious: CheckInEnergy.normal,
      );
      expect(review.rule, ReviewRule.build);
    });

    test('it applies to every goal kind', () {
      final fitter = reviewOf(
        kind: GoalKind.getFitter,
        levers: fitterLevers(),
        foodOrWeight: true,
        foodOrWeightPrevious: true,
      );
      expect(fitter.rule, ReviewRule.pauseCheckIn);
      final sleeper = reviewOf(
        kind: GoalKind.sleepBetter,
        levers: [wakeWeek(405, 6), sleepWeek(690, 5)],
        energy: CheckInEnergy.low,
        energyPrevious: CheckInEnergy.low,
      );
      expect(sleeper.rule, ReviewRule.pauseCheckIn);
    });
  });

  group('reviewWeek rule 4 recoveryWeek', () {
    const lows = <int?>[52, 49, 58, 54, 61, 50, 66];

    test('four readiness days under 55 give a recovery week', () {
      final review = reviewOf(readiness: lows);
      expect(review.rule, ReviewRule.recoveryWeek);
      expect(review.action, ReviewAction.recoveryWeek);
      expect(review.change, isNull);
      expect(review.pauseDays, isNull);
      expect(review.needsConsent, isFalse);
    });

    test('a repeated recovery week pauses 14 days', () {
      final review = reviewOf(readiness: lows, recoveryPrevious: true);
      expect(review.rule, ReviewRule.recoveryWeek);
      expect(review.action, ReviewAction.pause);
      expect(review.pauseDays, 14);
      expect(review.change, isNull);
    });

    test('a 55 in place of the 54 leaves three lows and builds', () {
      final review = reviewOf(readiness: const [52, 49, 58, 55, 61, 50, 66]);
      expect(review.rule, ReviewRule.build);
    });

    test('null readiness days are neutral, not low', () {
      final withNulls = reviewOf(
        readiness: const [null, null, 52, 49, 54, 50, 70],
      );
      expect(withNulls.rule, ReviewRule.recoveryWeek);
      final threeLowsAndNulls = reviewOf(
        readiness: const [null, null, null, 52, 49, 54, 70],
      );
      expect(threeLowsAndNulls.rule, ReviewRule.build);
    });

    test('it applies to every goal kind', () {
      final review = reviewOf(
        kind: GoalKind.sleepBetter,
        levers: [wakeWeek(405, 6), sleepWeek(690, 5)],
        readiness: lows,
      );
      expect(review.rule, ReviewRule.recoveryWeek);
    });

    test('it comes before ease', () {
      final review = reviewOf(
        rate: fromPercents(0.8, 1.0),
        capPercent: 1.0,
        readiness: lows,
      );
      expect(review.rule, ReviewRule.recoveryWeek);
    });
  });

  group('reviewWeek rule 5 ease', () {
    test('a loss above the band under the cap eases with no change', () {
      final review = reviewOf(
        week: 3,
        levers: [strengthWeek(2, 2), sleepWeek(690, 6)],
        rate: fromPercents(0.8, 1.0),
        capPercent: 1.0,
      );
      expect(review.rule, ReviewRule.ease);
      expect(review.action, ReviewAction.ease);
      expect(review.change, isNull);
      expect(review.pauseDays, isNull);
      expect(review.needsConsent, isFalse);
    });

    test('with the body off it does not ease', () {
      final review = reviewOf(
        week: 3,
        levers: [strengthWeek(2, 2), sleepWeek(690, 6)],
        rate: fromPercents(0.8, 1.0),
        capPercent: 1.0,
        bodyOn: false,
      );
      expect(review.rule, ReviewRule.holdBuilding);
    });
  });

  group('reviewWeek rule 6 build', () {
    test('week 4 with steps at 9,000 and 5 days raises steps to 10,000', () {
      final review = reviewOf();
      expect(review.rule, ReviewRule.build);
      expect(review.action, ReviewAction.nextStep);
      expectChange(review.change, LeverKind.steps, 9000, 10000);
      expect(review.needsConsent, isTrue);
      expect(review.adherence, closeTo(1, tight));
      expect(review.pauseDays, isNull);
      expect(review.bodyOff, isFalse);
    });

    test('week 3 with two levers adds steps at 9,000', () {
      final review = reviewOf(
        week: 3,
        levers: [strengthWeek(2, 2), sleepWeek(690, 6)],
      );
      expect(review.rule, ReviewRule.build);
      expectChange(review.change, LeverKind.steps, null, 9000);
      expect(review.needsConsent, isTrue);
    });

    test('week 2 with strength only adds the sleep window at 690', () {
      final review = reviewOf(week: 2, levers: [strengthWeek(2, 2)]);
      expect(review.rule, ReviewRule.build);
      expectChange(review.change, LeverKind.sleepWindow, null, 690);
    });

    test('week 4 with steps at 10,000 raises the sleep window to 675', () {
      final review = reviewOf(
        levers: [strengthWeek(2, 2), sleepWeek(690, 6), stepsWeek(10000, 5)],
      );
      expect(review.rule, ReviewRule.build);
      expectChange(review.change, LeverKind.sleepWindow, 690, 675);
    });

    test('week 5 under lose fat no longer builds and holds on track', () {
      final review = reviewOf(
        week: 5,
        levers: [strengthWeek(2, 2), sleepWeek(690, 6), stepsWeek(10000, 5)],
      );
      expect(review.rule, ReviewRule.holdOnTrack);
      expect(review.action, ReviewAction.hold);
      expect(review.change, isNull);
      expect(review.needsConsent, isFalse);
    });

    test('get fitter builds at week 4 and raises effort 150 to 165', () {
      final review = reviewOf(
        kind: GoalKind.getFitter,
        levers: fitterLevers(),
        adherencePrevious: 1.0,
      );
      expect(review.rule, ReviewRule.build);
      expect(review.action, ReviewAction.nextStep);
      expectChange(review.change, LeverKind.effortPoints, 150, 165);
      expect(review.needsConsent, isTrue);
    });

    test('get fitter with three raises in a row raises steps instead', () {
      final review = reviewOf(
        kind: GoalKind.getFitter,
        levers: fitterLevers(),
        adherencePrevious: 1.0,
        effortRaisesInRow: 3,
      );
      expect(review.rule, ReviewRule.build);
      expectChange(review.change, LeverKind.steps, 9000, 10000);
    });

    test('get fitter still builds at week 9', () {
      final review = reviewOf(
        kind: GoalKind.getFitter,
        week: 9,
        levers: fitterLevers(),
        adherencePrevious: 1.0,
      );
      expect(review.rule, ReviewRule.build);
      expectChange(review.change, LeverKind.effortPoints, 150, 165);
    });

    test('get fitter builds with the body off', () {
      final review = reviewOf(
        kind: GoalKind.getFitter,
        levers: fitterLevers(),
        adherencePrevious: 1.0,
        bodyOn: false,
      );
      expect(review.rule, ReviewRule.build);
    });

    test('sleep better builds at week 2 adding the sleep window at 690', () {
      final review = reviewOf(
        kind: GoalKind.sleepBetter,
        week: 2,
        levers: [wakeWeek(405, 5)],
      );
      expect(review.rule, ReviewRule.build);
      expectChange(review.change, LeverKind.sleepWindow, null, 690);
      expect(review.needsConsent, isTrue);
    });

    test('sleep better builds late in the plan raising 690 to 675', () {
      final review = reviewOf(
        kind: GoalKind.sleepBetter,
        week: 9,
        levers: [wakeWeek(405, 6), sleepWeek(690, 5)],
      );
      expect(review.rule, ReviewRule.build);
      expectChange(review.change, LeverKind.sleepWindow, 690, 675);
    });

    test('sleep better with the sleep window at 585 is not raised', () {
      final review = reviewOf(
        kind: GoalKind.sleepBetter,
        week: 9,
        levers: [wakeWeek(405, 6), sleepWeek(585, 5)],
      );
      expect(review.rule, ReviewRule.holdOther);
      expect(review.change, isNull);
    });

    test('a null next step falls through to hold on track under lose fat', () {
      final review = reviewOf(week: 3, levers: ceilingLevers);
      expect(review.rule, ReviewRule.holdOnTrack);
      expect(review.action, ReviewAction.hold);
      expect(review.change, isNull);
    });

    test('a null next step falls through to hold other under get fitter', () {
      final review = reviewOf(
        kind: GoalKind.getFitter,
        levers: fitterLevers(
          effortTarget: 300,
          effortDone: 300,
          stepsTarget: 10000,
          strengthTarget: 4,
          strengthDone: 4,
        ),
        adherencePrevious: 1.0,
      );
      expect(review.rule, ReviewRule.holdOther);
      expect(review.change, isNull);
    });
  });

  group('reviewWeek rule 7 holdBuilding', () {
    test('no rate in week 3 still builds', () {
      final review = reviewOf(
        week: 3,
        levers: [strengthWeek(2, 2), sleepWeek(690, 6)],
        rate: null,
      );
      expect(review.rule, ReviewRule.build);
      expectChange(review.change, LeverKind.steps, null, 9000);
    });

    test('no rate in week 5 holds building', () {
      final review = reviewOf(week: 5, rate: null);
      expect(review.rule, ReviewRule.holdBuilding);
      expect(review.action, ReviewAction.hold);
      expect(review.change, isNull);
      expect(review.needsConsent, isFalse);
      expect(review.bodyOff, isFalse);
    });

    test('the body off in week 3 holds building and sets body off', () {
      final review = reviewOf(
        week: 3,
        levers: [strengthWeek(2, 2), sleepWeek(690, 6)],
        bodyOn: false,
      );
      expect(review.rule, ReviewRule.holdBuilding);
      expect(review.action, ReviewAction.hold);
      expect(review.change, isNull);
      expect(review.bodyOff, isTrue);
      expect(review.needsConsent, isFalse);
    });

    test('the body off in week 4 holds building as well', () {
      final review = reviewOf(bodyOn: false);
      expect(review.rule, ReviewRule.holdBuilding);
      expect(review.bodyOff, isTrue);
    });

    test('the protections come before the body off', () {
      expect(
        reviewOf(
          bodyOn: false,
          rate: fromPercents(1.11, 1.5),
          previousPercentLow: 0.56,
        ).rule,
        ReviewRule.pauseFastLoss,
      );
      expect(reviewOf(bodyOn: false, bmiValue: 18.4).rule, ReviewRule.end);
      expect(
        reviewOf(
          bodyOn: false,
          foodOrWeight: true,
          foodOrWeightPrevious: true,
        ).rule,
        ReviewRule.pauseCheckIn,
      );
      expect(
        reviewOf(
          bodyOn: false,
          readiness: const [50, 50, 50, 50, 70, 70, 70],
        ).rule,
        ReviewRule.recoveryWeek,
      );
    });
  });

  group('reviewWeek rule 8 shrink', () {
    test('strength 1 of 2, sleep 3 and steps 5 shrink and drop the sleep', () {
      final review = reviewOf(
        levers: [strengthWeek(2, 1), sleepWeek(690, 3), stepsWeek(9000, 5)],
      );
      expect(review.rule, ReviewRule.shrink);
      expect(review.action, ReviewAction.shrink);
      expect(review.adherence, closeTo(1 / 3, tight));
      expectChange(review.change, LeverKind.sleepWindow, 690, null);
      expect(review.needsConsent, isTrue);
    });

    test('strength 0 of 2, sleep 4 and steps 3 drop the steps', () {
      final review = reviewOf(
        levers: [strengthWeek(2, 0), sleepWeek(690, 4), stepsWeek(9000, 3)],
      );
      expect(review.rule, ReviewRule.shrink);
      expectChange(review.change, LeverKind.steps, 9000, null);
    });

    test('two of three fit holds on track and does not shrink', () {
      final review = reviewOf(
        levers: [strengthWeek(2, 2), sleepWeek(690, 6), stepsWeek(9000, 3)],
      );
      expect(review.rule, ReviewRule.holdOnTrack);
      expect(review.action, ReviewAction.hold);
      expect(review.change, isNull);
    });

    test('two active levers never shrink, even at an adherence of 0.5', () {
      final review = reviewOf(levers: [strengthWeek(2, 1), sleepWeek(690, 6)]);
      expect(review.rule, ReviewRule.holdOnTrack);
    });

    test('under lose fat strength is never the removed lever', () {
      final layouts = [
        [strengthWeek(2, 0), sleepWeek(690, 7), stepsWeek(9000, 7)],
        [strengthWeek(2, 0), sleepWeek(690, 0), stepsWeek(9000, 0)],
        [strengthWeek(4, 0), sleepWeek(690, 1), stepsWeek(9000, 2)],
      ];
      for (final levers in layouts) {
        final review = reviewOf(levers: levers);
        expect(review.rule, ReviewRule.shrink);
        expect(review.change!.kind, isNot(LeverKind.strengthDays));
        expect(review.change!.to, isNull);
      }
    });

    test('get fitter shrinks and removes the lowest ratio', () {
      final review = reviewOf(
        kind: GoalKind.getFitter,
        levers: [effortWeek(150, 100), stepsWeek(9000, 5), strengthWeek(2, 1)],
      );
      expect(review.rule, ReviewRule.shrink);
      expectChange(review.change, LeverKind.strengthDays, 2, null);
    });

    test('sleep better has at most two levers and never shrinks', () {
      final review = reviewOf(
        kind: GoalKind.sleepBetter,
        week: 6,
        levers: [wakeWeek(405, 1), sleepWeek(690, 1)],
      );
      expect(review.rule, ReviewRule.holdOther);
    });
  });

  group('reviewWeek rule 9 holdOnTrack', () {
    test('an on track plan with levers that fit holds', () {
      final review = reviewOf(week: 6, levers: ceilingLevers);
      expect(review.rule, ReviewRule.holdOnTrack);
      expect(review.action, ReviewAction.hold);
      expect(review.change, isNull);
      expect(review.needsConsent, isFalse);
    });
  });

  group('reviewWeek rule 10 stepSlow', () {
    final slow = fromPercents(0.10, 0.20);

    test('week 6 below the band with 3 of 3 raises steps to 10,000', () {
      final review = reviewOf(week: 6, rate: slow);
      expect(review.rule, ReviewRule.stepSlow);
      expect(review.action, ReviewAction.nextStep);
      expectChange(review.change, LeverKind.steps, 9000, 10000);
      expect(review.needsConsent, isTrue);
    });

    test('week 6 below the band with 2 of 3 holds other', () {
      final review = reviewOf(
        week: 6,
        rate: slow,
        levers: [strengthWeek(2, 2), sleepWeek(690, 3), stepsWeek(9000, 5)],
      );
      expect(review.rule, ReviewRule.holdOther);
      expect(review.action, ReviewAction.hold);
      expect(review.change, isNull);
      expect(review.needsConsent, isFalse);
    });

    test('a null next step falls through to hold other', () {
      final review = reviewOf(week: 6, rate: slow, levers: ceilingLevers);
      expect(review.rule, ReviewRule.holdOther);
      expect(review.change, isNull);
    });

    test('inside the first four weeks a slow plan still builds', () {
      final review = reviewOf(rate: slow);
      expect(review.rule, ReviewRule.build);
    });
  });

  group('reviewWeek rule 11 holdOther', () {
    test(
      'get fitter with two of three fit holds other past the plan start',
      () {
        final review = reviewOf(
          kind: GoalKind.getFitter,
          week: 6,
          levers: fitterLevers(effortDone: 100),
          adherencePrevious: 1.0,
        );
        expect(review.rule, ReviewRule.holdOther);
        expect(review.action, ReviewAction.hold);
        expect(review.change, isNull);
      },
    );

    test('sleep better with the wake at 6 and the sleep at 4 holds other', () {
      final review = reviewOf(
        kind: GoalKind.sleepBetter,
        week: 3,
        levers: [wakeWeek(405, 6), sleepWeek(690, 4)],
      );
      expect(review.rule, ReviewRule.holdOther);
      expect(review.action, ReviewAction.hold);
      expect(review.change, isNull);
      expect(review.adherence, closeTo(0.5, tight));
    });
  });

  group('reviewWeek precedence', () {
    final fast = fromPercents(1.11, 1.5);

    test('a bmi of 18.4 with a fast loss ends the goal', () {
      final review = reviewOf(
        bmiValue: 18.4,
        rate: fast,
        previousPercentLow: 0.56,
      );
      expect(review.rule, ReviewRule.end);
    });

    test('a bmi of 18.5 with a fast loss pauses instead', () {
      final review = reviewOf(
        bmiValue: 18.5,
        rate: fast,
        previousPercentLow: 0.56,
      );
      expect(review.rule, ReviewRule.pauseFastLoss);
    });

    test('a fast loss with food yes twice pauses for the fast loss', () {
      final review = reviewOf(
        rate: fast,
        previousPercentLow: 0.56,
        foodOrWeight: true,
        foodOrWeightPrevious: true,
      );
      expect(review.rule, ReviewRule.pauseFastLoss);
      expect(review.pauseDays, 28);
    });

    test('food yes twice with low readiness pauses on the check in', () {
      final review = reviewOf(
        foodOrWeight: true,
        foodOrWeightPrevious: true,
        readiness: const [52, 49, 54, 50, 70, 70, 70],
      );
      expect(review.rule, ReviewRule.pauseCheckIn);
      expect(review.pauseDays, isNull);
    });

    test('low readiness with a repeated recovery beats the ease', () {
      final review = reviewOf(
        rate: fromPercents(0.8, 1.0),
        capPercent: 1.0,
        readiness: const [52, 49, 54, 50, 70, 70, 70],
        recoveryPrevious: true,
      );
      expect(review.rule, ReviewRule.recoveryWeek);
      expect(review.pauseDays, 14);
    });

    test('an ease beats a build with 2 of 2 in week 3', () {
      final review = reviewOf(
        week: 3,
        levers: [strengthWeek(2, 2), sleepWeek(690, 6)],
        rate: fromPercents(0.8, 1.0),
        capPercent: 1.0,
      );
      expect(review.rule, ReviewRule.ease);
      expect(review.change, isNull);
    });

    test('the build beats the shrink and the hold rules', () {
      expect(reviewOf().rule, ReviewRule.build);
      expect(reviewOf(week: 4, rate: null).rule, ReviewRule.build);
    });
  });

  group('Review.needsConsent', () {
    test('a change under a rule that is not a protection needs consent', () {
      expect(reviewOf().needsConsent, isTrue);
      expect(
        reviewOf(
          levers: [strengthWeek(2, 1), sleepWeek(690, 3), stepsWeek(9000, 5)],
        ).needsConsent,
        isTrue,
      );
    });

    test('no change needs no consent', () {
      expect(reviewOf(week: 5).needsConsent, isFalse);
      expect(reviewOf(bmiValue: 18.4).needsConsent, isFalse);
    });
  });

  group('ReviewRule', () {
    test('the rules run in the order of the table', () {
      expect(ReviewRule.values, [
        ReviewRule.end,
        ReviewRule.pauseFastLoss,
        ReviewRule.pauseCheckIn,
        ReviewRule.recoveryWeek,
        ReviewRule.ease,
        ReviewRule.build,
        ReviewRule.holdBuilding,
        ReviewRule.shrink,
        ReviewRule.holdOnTrack,
        ReviewRule.stepSlow,
        ReviewRule.holdOther,
      ]);
    });

    test('number runs from 1 to 11 in enum order', () {
      expect(
        [for (final rule in ReviewRule.values) rule.number],
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
      );
    });

    test('only the first four are protections', () {
      expect(ReviewRule.values.where((rule) => rule.protection).toList(), [
        ReviewRule.end,
        ReviewRule.pauseFastLoss,
        ReviewRule.pauseCheckIn,
        ReviewRule.recoveryWeek,
      ]);
    });
  });

  group('the metrics library exports', () {
    test('every constant of the goal review', () {
      expect(goalDailyFitDays, 5);
      expect(goalShrinkBelow, 0.6);
      expect(goalStepFrom, 0.8);
      expect(goalMaxLevers, 3);
      expect(goalBuildWeeks, 4);
      expect(goalStepsStep, 1000);
      expect(goalStepsCeiling, 10000);
      expect(goalStepsRound, 500);
      expect(goalEffortStepPercent, 10);
      expect(goalEffortStepMin, 15);
      expect(goalEffortCeiling, 300);
      expect(goalEffortRaisesBeforeHold, 3);
      expect(goalStrengthFloor, 2);
      expect(goalStrengthCeiling, 4);
      expect(goalSleepStepMinutes, 15);
      expect(goalSleepMinMinutes, 420);
      expect(goalSleepMaxMinutes, 540);
      expect(goalWakeToleranceMinutes, 30);
      expect(goalLowReadinessDays, 4);
      expect(goalFastLossPauseDays, 28);
      expect(goalRecoveryPauseDays, 14);
    });

    test('every enum of the goal review', () {
      expect(LeverKind.values, [
        LeverKind.strengthDays,
        LeverKind.sleepWindow,
        LeverKind.steps,
        LeverKind.effortPoints,
        LeverKind.wakeTime,
      ]);
      expect(LeverUnit.values, [
        LeverUnit.daysPerWeek,
        LeverUnit.minutesAfterNoon,
        LeverUnit.stepsPerDay,
        LeverUnit.pointsPerWeek,
        LeverUnit.minutesAfterMidnight,
      ]);
      expect(LeverCadence.values, [LeverCadence.daily, LeverCadence.weekly]);
      expect(CheckInEnergy.values, [
        CheckInEnergy.low,
        CheckInEnergy.normal,
        CheckInEnergy.good,
      ]);
      expect(ReviewAction.values, [
        ReviewAction.end,
        ReviewAction.pause,
        ReviewAction.recoveryWeek,
        ReviewAction.hold,
        ReviewAction.ease,
        ReviewAction.shrink,
        ReviewAction.nextStep,
      ]);
    });
  });
}
