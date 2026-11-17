import 'dart:math' as math;

import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

import 'food_nights.dart';

const tight = 1e-9;

LinkComparison prototype(
  FoodLink link,
  NightOutcome outcome, {
  List<FoodNight>? nights,
}) => compareLink(
  link: link,
  outcome: outcome,
  lastNight: prototypeLastNight,
  nights: nights ?? prototypeNights,
  meals: prototypeMeals,
);

LinkComparison book(NightBook book, FoodLink link, NightOutcome outcome) =>
    compareLink(
      link: link,
      outcome: outcome,
      lastNight: day(89),
      nights: book.nights,
      meals: book.meals,
    );

Matcher isPattern({
  required int pairs,
  required double mean,
  required double low,
  required double high,
  double tolerance = 0.005,
}) => isA<LinkPattern>()
    .having((r) => r.pairs, 'pairs', pairs)
    .having((r) => r.mean, 'mean', closeTo(mean, tolerance))
    .having((r) => r.low, 'low', closeTo(low, tolerance))
    .having((r) => r.high, 'high', closeTo(high, tolerance));

Matcher isNoClearDifference({
  required int pairs,
  required double mean,
  required double low,
  required double high,
  double tolerance = 0.005,
}) => isA<LinkNoClearDifference>()
    .having((r) => r.pairs, 'pairs', pairs)
    .having((r) => r.mean, 'mean', closeTo(mean, tolerance))
    .having((r) => r.low, 'low', closeTo(low, tolerance))
    .having((r) => r.high, 'high', closeTo(high, tolerance));

Matcher isCollecting({required int pairs, required int minimum}) =>
    isA<LinkCollecting>()
        .having((r) => r.pairs, 'pairs', pairs)
        .having((r) => r.minimum, 'minimum', minimum);

enum Exposure { heavy, alcohol, caffeine }

// Exposed nights on Monday and Wednesday of each week, each paired with the
// next night, so pair i holds values[i] as (exposed, control).
NightBook paired(
  List<(double, double)> values,
  NightOutcome outcome, {
  Exposure exposure = Exposure.heavy,
}) {
  final book = NightBook();
  for (final (i, (exposed, control)) in values.indexed) {
    final o = 7 * (i ~/ 2) + (i.isEven ? 0 : 2);
    _addNight(book, o, exposed, outcome, exposure);
    _addNight(book, o + 1, control, outcome, null);
  }
  return book;
}

void _addNight(
  NightBook book,
  int o,
  double value,
  NightOutcome outcome,
  Exposure? exposure,
) {
  book.add(
    o,
    heavy: exposure == Exposure.heavy,
    alcohol: exposure == Exposure.alcohol ? MealAlcohol.threeOrMore : null,
    extra: [if (exposure == Exposure.caffeine) caffeineAt(o, 15 * 60)],
    heartRate: outcome == NightOutcome.heartRate ? value : 55,
    hrv: outcome == NightOutcome.hrv ? value : 50,
    onset: outcome == NightOutcome.onset ? value.round() : 23 * 60 + 30,
  );
}

// HR differences d alternating over [count] pairs, control 55 bpm.
List<(double, double)> hrDiffs(double a, double b, {int count = 14}) => [
  for (var i = 0; i < count; i++) (55 + (i.isEven ? a : b), 55),
];

List<FoodNight> replaceNight(int o, FoodNight night) => [
  for (final each in prototypeNights)
    if (dayOf(each.day) == o) night else each,
];

FoodNight prototypeWith(
  int o, {
  bool noHeartRate = false,
  bool noOnset = false,
  double? hrv,
}) {
  final base = prototypeNight(o);
  return FoodNight(
    day: base.day,
    heartRate: noHeartRate ? null : base.heartRate,
    hrv: hrv ?? base.hrv,
    sleepOnset: noOnset ? null : base.sleepOnset,
  );
}

void main() {
  group('F2 acceptance on the prototype fixture (decision 6)', () {
    test('matchPairs reproduces the prototype pairs for all 5 links', () {
      for (final MapEntry(key: link, value: expected)
          in prototypePairs.entries) {
        final pairs = matchPairs(
          link: link,
          lastNight: prototypeLastNight,
          nights: prototypeNights,
          meals: prototypeMeals,
        );
        expect(
          [for (final p in pairs) (dayOf(p.exposed), dayOf(p.control))],
          expected,
          reason: '$link',
        );
      }
    });

    test('alcohol 3+, 12 pairs: HR +5.08 bpm (1.57 to 8.60) is a pattern', () {
      expect(
        prototype(FoodLink.alcoholThreeOrMore, NightOutcome.heartRate),
        isPattern(pairs: 12, mean: 5.08, low: 1.57, high: 8.60),
      );
    });

    test('alcohol 3+, 12 pairs: HRV -19.5% (-25.2 to -13.4), in logs, is a '
        'pattern', () {
      expect(
        prototype(FoodLink.alcoholThreeOrMore, NightOutcome.hrv),
        isPattern(
          pairs: 12,
          mean: -19.5,
          low: -25.2,
          high: -13.4,
          tolerance: 0.05,
        ),
      );
    });

    test('late last meal, 16 pairs: HR +4.19 bpm (1.59 to 6.78) is a '
        'pattern', () {
      expect(
        prototype(FoodLink.lateLastMeal, NightOutcome.heartRate),
        isPattern(pairs: 16, mean: 4.19, low: 1.59, high: 6.78),
      );
    });

    test(
      'late last meal, 16 pairs: HRV -7.5% (-13.1 to -1.6) is a pattern',
      () {
        expect(
          prototype(FoodLink.lateLastMeal, NightOutcome.hrv),
          isPattern(
            pairs: 16,
            mean: -7.53,
            low: -13.11,
            high: -1.59,
            tolerance: 0.01,
          ),
        );
      },
    );

    test('caffeine after 14h, 16 pairs: onset -0.25 min (-13.56 to 13.06) is '
        'no clear difference', () {
      expect(
        prototype(FoodLink.caffeineAfter14, NightOutcome.onset),
        isNoClearDifference(pairs: 16, mean: -0.25, low: -13.56, high: 13.06),
      );
    });

    test('caffeine after 14h, 16 pairs: HR -1.81 (-4.87 to 1.25) is no clear '
        'difference', () {
      expect(
        prototype(FoodLink.caffeineAfter14, NightOutcome.heartRate),
        isNoClearDifference(pairs: 16, mean: -1.81, low: -4.87, high: 1.25),
      );
    });

    test('heavy dinner at 9 of 14 pairs is collecting', () {
      for (final outcome in NightOutcome.values) {
        expect(
          prototype(FoodLink.heavyDinner, outcome),
          isCollecting(pairs: 9, minimum: 14),
          reason: '$outcome',
        );
      }
    });

    test('alcohol 1 to 2 at 7 of 10 pairs is collecting', () {
      for (final outcome in NightOutcome.values) {
        expect(
          prototype(FoodLink.alcoholOneToTwo, outcome),
          isCollecting(pairs: 7, minimum: 10),
          reason: '$outcome',
        );
      }
    });
  });

  group('FD4 and the outcome a night is missing', () {
    test('a night with no onset leaves only the onset comparison', () {
      final nights = replaceNight(28, prototypeWith(28, noOnset: true));
      expect(
        prototype(FoodLink.caffeineAfter14, NightOutcome.onset, nights: nights),
        isNoClearDifference(pairs: 15, mean: -1.6, low: -15.32, high: 12.12),
      );
      expect(
        prototype(
          FoodLink.caffeineAfter14,
          NightOutcome.heartRate,
          nights: nights,
        ),
        isNoClearDifference(pairs: 16, mean: -1.81, low: -4.87, high: 1.25),
      );
      expect(
        prototype(FoodLink.caffeineAfter14, NightOutcome.hrv, nights: nights),
        isA<LinkComparison>().having((r) => r.pairs, 'pairs', 16),
      );
      expect(
        prototype(
          FoodLink.alcoholThreeOrMore,
          NightOutcome.heartRate,
          nights: nights,
        ),
        isPattern(pairs: 12, mean: 5.08, low: 1.57, high: 8.60),
      );
    });

    test('a pair whose night has no onset is still matched; it only drops '
        'from the onset numbers', () {
      final nights = replaceNight(28, prototypeWith(28, noOnset: true));
      final pairs = matchPairs(
        link: FoodLink.caffeineAfter14,
        lastNight: prototypeLastNight,
        nights: nights,
        meals: prototypeMeals,
      );
      expect([
        for (final p in pairs) (dayOf(p.exposed), dayOf(p.control)),
      ], prototypePairs[FoodLink.caffeineAfter14]);
    });

    test(
      'a night with no heart rate leaves only the heart rate comparison',
      () {
        final nights = replaceNight(28, prototypeWith(28, noHeartRate: true));
        expect(
          prototype(
            FoodLink.caffeineAfter14,
            NightOutcome.heartRate,
            nights: nights,
          ),
          isNoClearDifference(pairs: 15, mean: -2.13, low: -5.27, high: 1.01),
        );
        expect(
          prototype(
            FoodLink.caffeineAfter14,
            NightOutcome.onset,
            nights: nights,
          ),
          isNoClearDifference(pairs: 16, mean: -0.25, low: -13.56, high: 13.06),
        );
      },
    );

    test('a night with HRV 0 has no HRV: the pair drops, the numbers stay '
        'finite', () {
      final nights = replaceNight(28, prototypeWith(28, hrv: 0));
      final result = prototype(
        FoodLink.caffeineAfter14,
        NightOutcome.hrv,
        nights: nights,
      );
      expect(
        result,
        isNoClearDifference(pairs: 15, mean: 5.05, low: -2.86, high: 13.61),
      );
    });
  });

  group('minimum pairs: 10 for alcohol, 14 for the rest (decision 6)', () {
    test('with no nights every link is collecting at 0 with its minimum', () {
      const minimum = {
        FoodLink.alcoholThreeOrMore: 10,
        FoodLink.alcoholOneToTwo: 10,
        FoodLink.lateLastMeal: 14,
        FoodLink.caffeineAfter14: 14,
        FoodLink.heavyDinner: 14,
      };
      expect(FoodLink.values, hasLength(5));
      for (final link in FoodLink.values) {
        expect(
          book(NightBook(), link, NightOutcome.heartRate),
          isCollecting(pairs: 0, minimum: minimum[link]!),
          reason: '$link',
        );
      }
    });

    test('alcohol 3+ at 9 pairs is collecting, at 10 it decides', () {
      final nine = paired(
        hrDiffs(4, 6, count: 9),
        NightOutcome.heartRate,
        exposure: Exposure.alcohol,
      );
      expect(
        book(nine, FoodLink.alcoholThreeOrMore, NightOutcome.heartRate),
        isCollecting(pairs: 9, minimum: 10),
      );
      final ten = paired(
        hrDiffs(4, 6, count: 10),
        NightOutcome.heartRate,
        exposure: Exposure.alcohol,
      );
      expect(
        book(ten, FoodLink.alcoholThreeOrMore, NightOutcome.heartRate),
        isA<LinkPattern>()
            .having((r) => r.pairs, 'pairs', 10)
            .having((r) => r.mean, 'mean', closeTo(5, tight)),
      );
    });

    test('heavy dinner at 13 pairs is collecting, at 14 it decides', () {
      final thirteen = paired(hrDiffs(4, 6, count: 13), NightOutcome.heartRate);
      expect(
        book(thirteen, FoodLink.heavyDinner, NightOutcome.heartRate),
        isCollecting(pairs: 13, minimum: 14),
      );
      final fourteen = paired(hrDiffs(4, 6), NightOutcome.heartRate);
      expect(
        book(fourteen, FoodLink.heavyDinner, NightOutcome.heartRate),
        isA<LinkPattern>().having((r) => r.pairs, 'pairs', 14),
      );
    });
  });

  group('state rule: pattern when the 99% interval excludes 0 and |mean| is '
      'at least the smallest meaningful difference (prototype stat)', () {
    test('an interval that crosses zero is no clear difference even with a '
        'mean of +3 bpm', () {
      final result = book(
        paired(hrDiffs(13, -7), NightOutcome.heartRate),
        FoodLink.heavyDinner,
        NightOutcome.heartRate,
      );
      expect(
        result,
        isA<LinkNoClearDifference>()
            .having((r) => r.pairs, 'pairs', 14)
            .having((r) => r.mean, 'mean', closeTo(3, tight))
            .having((r) => r.low, 'low', lessThan(0))
            .having((r) => r.high, 'high', greaterThan(0)),
      );
    });

    test('a whole range inside 2 bpm is no clear difference even though it '
        'excludes zero', () {
      final result = book(
        paired(hrDiffs(1, 2), NightOutcome.heartRate),
        FoodLink.heavyDinner,
        NightOutcome.heartRate,
      );
      expect(
        result,
        isA<LinkNoClearDifference>()
            .having((r) => r.mean, 'mean', closeTo(1.5, tight))
            .having((r) => r.low, 'low', greaterThan(0))
            .having((r) => r.high, 'high', lessThan(2)),
      );
    });

    test('the mean decides, not the range: a mean of 1.7 bpm is no clear '
        'difference even when the range reaches past 2', () {
      final result = book(
        paired(hrDiffs(0.5, 2.9), NightOutcome.heartRate),
        FoodLink.heavyDinner,
        NightOutcome.heartRate,
      );
      expect(
        result,
        isA<LinkNoClearDifference>()
            .having((r) => r.mean, 'mean', closeTo(1.7, tight))
            .having((r) => r.low, 'low', greaterThan(0))
            .having((r) => r.high, 'high', greaterThan(2)),
      );
    });

    test('a mean of exactly 2 bpm with the interval above zero is a '
        'pattern', () {
      final result = book(
        paired(hrDiffs(1, 3), NightOutcome.heartRate),
        FoodLink.heavyDinner,
        NightOutcome.heartRate,
      );
      expect(
        result,
        isA<LinkPattern>()
            .having((r) => r.mean, 'mean', 2)
            .having((r) => r.low, 'low', allOf(greaterThan(0), lessThan(2))),
      );
    });

    test('a mean of exactly -2 bpm with the interval below zero is a '
        'pattern', () {
      final result = book(
        paired(hrDiffs(-1, -3), NightOutcome.heartRate),
        FoodLink.heavyDinner,
        NightOutcome.heartRate,
      );
      expect(
        result,
        isA<LinkPattern>()
            .having((r) => r.mean, 'mean', -2)
            .having((r) => r.high, 'high', lessThan(0)),
      );
    });

    test('the interval is mean ± t99(n - 1) × sd / √n', () {
      final result = book(
        paired(hrDiffs(1, 3), NightOutcome.heartRate),
        FoodLink.heavyDinner,
        NightOutcome.heartRate,
      );
      final half = t99(13) * math.sqrt(14 / 13) / math.sqrt(14);
      expect(
        result,
        isA<LinkPattern>()
            .having((r) => r.low, 'low', closeTo(2 - half, tight))
            .having((r) => r.high, 'high', closeTo(2 + half, tight)),
      );
    });

    test('HRV is compared in percent: -9% is a pattern though each night '
        'moves under 5 ms', () {
      final values = [
        for (var i = 0; i < 14; i++) (i.isEven ? 18.0 : 18.4, 20.0),
      ];
      final logs = [math.log(18 / 20), math.log(18.4 / 20)];
      final expected = (math.exp((logs[0] + logs[1]) / 2) - 1) * 100;
      expect(
        book(
          paired(values, NightOutcome.hrv),
          FoodLink.heavyDinner,
          NightOutcome.hrv,
        ),
        isA<LinkPattern>().having(
          (r) => r.mean,
          'mean',
          closeTo(expected, tight),
        ),
      );
    });

    test('HRV -3% is no clear difference though each night moves 4 to '
        '8 ms', () {
      final values = [
        for (var i = 0; i < 14; i++) (i.isEven ? 192.0 : 196.0, 200.0),
      ];
      expect(
        book(
          paired(values, NightOutcome.hrv),
          FoodLink.heavyDinner,
          NightOutcome.hrv,
        ),
        isA<LinkNoClearDifference>()
            .having((r) => r.mean, 'mean', closeTo(-3.005, 0.001))
            .having((r) => r.high, 'high', lessThan(0)),
      );
    });

    test('onset 16 min later is a pattern, 13 min later is no clear '
        'difference', () {
      List<(double, double)> onsets(double a, double b) => [
        for (var i = 0; i < 14; i++) (1410 + (i.isEven ? a : b), 1410),
      ];
      expect(
        book(
          paired(
            onsets(15, 17),
            NightOutcome.onset,
            exposure: Exposure.caffeine,
          ),
          FoodLink.caffeineAfter14,
          NightOutcome.onset,
        ),
        isA<LinkPattern>().having((r) => r.mean, 'mean', closeTo(16, tight)),
      );
      expect(
        book(
          paired(
            onsets(12, 14),
            NightOutcome.onset,
            exposure: Exposure.caffeine,
          ),
          FoodLink.caffeineAfter14,
          NightOutcome.onset,
        ),
        isA<LinkNoClearDifference>().having(
          (r) => r.mean,
          'mean',
          closeTo(13, tight),
        ),
      );
    });

    test('onset after midnight is later, not 23 h earlier: 00:10 and 00:30 '
        'against 23:50 is +30 min', () {
      final values = [
        for (var i = 0; i < 14; i++) (i.isEven ? 1450.0 : 1470.0, 1430.0),
      ];
      expect(
        book(
          paired(values, NightOutcome.onset, exposure: Exposure.caffeine),
          FoodLink.caffeineAfter14,
          NightOutcome.onset,
        ),
        isA<LinkPattern>().having((r) => r.mean, 'mean', closeTo(30, tight)),
      );
    });
  });

  group('t99: two sided 99% Student t, 3 decimals', () {
    test('11 degrees of freedom gives 3.106', () {
      expect(t99(11), closeTo(3.106, 0.0005));
    });

    test('matches the prototype table from 5 to 25', () {
      const table = {
        5: 4.032, 6: 3.707, 7: 3.499, 8: 3.355, 9: 3.250, 10: 3.169, //
        11: 3.106, 12: 3.055, 13: 3.012, 14: 2.977, 15: 2.947, 16: 2.921,
        17: 2.898, 18: 2.878, 19: 2.861, 20: 2.845, 21: 2.831, 22: 2.819,
        23: 2.807, 24: 2.797, 25: 2.787,
      };
      for (final MapEntry(key: df, value: t) in table.entries) {
        expect(t99(df), closeTo(t, 0.0005), reason: 'df $df');
      }
    });

    test('covers 1 degree of freedom and the 45 pairs 90 nights can '
        'hold', () {
      const table = {
        1: 63.657, 2: 9.925, 3: 5.841, 4: 4.604, 30: 2.750, 40: 2.704, //
        44: 2.692, 60: 2.660, 120: 2.617,
      };
      for (final MapEntry(key: df, value: t) in table.entries) {
        expect(t99(df), closeTo(t, 0.001), reason: 'df $df');
      }
    });

    test('falls with df and stays above the normal 2.576', () {
      for (var df = 1; df < 200; df++) {
        expect(t99(df + 1), lessThanOrEqualTo(t99(df)), reason: 'df $df');
        expect(t99(df), greaterThan(2.5758), reason: 'df $df');
      }
    });

    test('0 degrees of freedom is an error', () {
      expect(() => t99(0), throwsArgumentError);
    });
  });

  group('decision 7: sleep stages never lead a comparison', () {
    test('the outcomes are nightly HR, HRV and onset only', () {
      expect(NightOutcome.values, [
        NightOutcome.heartRate,
        NightOutcome.hrv,
        NightOutcome.onset,
      ]);
    });
  });
}
