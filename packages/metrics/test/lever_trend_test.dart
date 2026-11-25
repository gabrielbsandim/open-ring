import 'dart:math' as math;

import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const end = LocalDate(2026, 11, 25);
const tolerance = 1e-9;

final dayStart = DateTime.utc(2026, 11, 24, 8);

double r(int x) => ((37 * x) % 11 - 5).toDouble();

List<DailyValue> series(
  int count,
  double Function(int x) value, {
  int from = 0,
}) => [
  for (var x = from; x < from + count; x++)
    (date: end.addDays(x - 89), value: value(x)),
];

LeverTrend trendOf(List<DailyValue> days) => theilSen(days, end: end)!;

StepBucket bucket(
  int index, {
  int steps = 10,
  int minutes = 15,
  int stepMinutes = 15,
}) => (
  start: dayStart.add(Duration(minutes: index * stepMinutes)),
  duration: Duration(minutes: minutes),
  steps: steps,
);

List<StepBucket> quarterHours(int count, {int steps = 10}) => [
  for (var i = 0; i < count; i++) bucket(i, steps: steps),
];

TimeSpan sleepSpan(int fromMinute, int toMinute) => (
  start: dayStart.add(Duration(minutes: fromMinute)),
  end: dayStart.add(Duration(minutes: toMinute)),
);

void main() {
  group('constants and enum values', () {
    test('the constants are the ones the spec names', () {
      expect(leverTrendWindowDays, 90);
      expect(leverTrendMinValidDays, 54);
      expect(leverTrendZ, 1.6448536269514722);
      expect(validStepDayWaking, const Duration(hours: 10));
    });

    test('each lever carries its minimum change', () {
      expect(RingLever.steps.minimumChange, 500);
      expect(RingLever.sleepRegularity.minimumChange, 5);
      expect(RingLever.restingHeartRate.minimumChange, 2);
      expect(RingLever.sleepDuration.minimumChange, 20);
    });
  });

  group('1. a rising steps series gives the slope, interval and fan', () {
    final trend = trendOf(series(90, (x) => 8150 + 12 * x + 150 * r(x)));

    test('slope is 12 and the interval is 9.115 to 16.167', () {
      expect(trend.slopePerDay, closeTo(12, tolerance));
      expect(trend.slopeLow, closeTo(9.115384615384615, tolerance));
      expect(trend.slopeHigh, closeTo(16.166666666666668, tolerance));
    });

    test('change over 90 days is 1080 within 820.38 and 1455', () {
      expect(trend.change, closeTo(1080, tolerance));
      expect(trend.changeLow, closeTo(820.3846153846154, tolerance));
      expect(trend.changeHigh, closeTo(1455, tolerance));
    });

    test('typical is the median 8684, centered on day 44.5 of 90', () {
      expect(trend.typical, closeTo(8684, tolerance));
      expect(trend.centerDay, closeTo(44.5, tolerance));
      expect(trend.validDays, 90);
    });

    test('steps is rising', () {
      expect(trend.direction(RingLever.steps), LeverDirection.rising);
    });

    test('the fan for steps is 10038.38 to 10673', () {
      final fan = trend.fan(RingLever.steps)!;
      expect(fan.low, closeTo(10038.384615384615, tolerance));
      expect(fan.high, closeTo(10673, tolerance));
    });
  });

  group('2. a significant change under the minimum stays stable', () {
    final trend = trendOf(series(90, (x) => 420 + x / 6 + 4 * r(x)));

    test('change is 15 within 8.08 and 25, excluding zero', () {
      expect(trend.change, closeTo(15, tolerance));
      expect(trend.changeLow, closeTo(8.076923076923109, tolerance));
      expect(trend.changeHigh, closeTo(25, tolerance));
      expect(trend.slopeLow, greaterThan(0));
    });

    test('sleep duration is stable because 15 is under 20', () {
      expect(trend.direction(RingLever.sleepDuration), LeverDirection.stable);
    });

    test('the fan for sleep duration is null', () {
      expect(trend.fan(RingLever.sleepDuration), isNull);
    });

    test('the same change clears the smaller sleep regularity minimum', () {
      expect(trend.direction(RingLever.sleepRegularity), LeverDirection.rising);
    });
  });

  group('3. an interval around zero is stable', () {
    final trend = trendOf(series(90, (x) => 54 + r(x)));

    test('interval is -1.73 to 2.17 over 90 days', () {
      expect(trend.changeLow, closeTo(-1.7307692307692308, tolerance));
      expect(trend.changeHigh, closeTo(2.168674698795181, tolerance));
      expect(trend.change, closeTo(0, tolerance));
      expect(trend.typical, closeTo(54, tolerance));
    });

    test('every lever is stable', () {
      for (final lever in RingLever.values) {
        expect(trend.direction(lever), LeverDirection.stable);
      }
    });
  });

  group('4. a falling resting heart rate', () {
    final trend = trendOf(series(90, (x) => 60 - x / 15 + r(x)));

    test('change is -6 within -7.73 and -3.50', () {
      expect(trend.change, closeTo(-6, tolerance));
      expect(trend.changeLow, closeTo(-7.730769230769222, tolerance));
      expect(trend.changeHigh, closeTo(-3.5, tolerance));
    });

    test('resting heart rate is falling', () {
      expect(
        trend.direction(RingLever.restingHeartRate),
        LeverDirection.falling,
      );
    });
  });

  group('5. the minimum valid days and the window', () {
    test('y = x on 54 days gives a trend', () {
      final trend = trendOf(series(54, (x) => x.toDouble()));

      expect(trend.validDays, 54);
      expect(trend.slopePerDay, closeTo(1, tolerance));
      expect(trend.slopeLow, closeTo(1, tolerance));
      expect(trend.slopeHigh, closeTo(1, tolerance));
      expect(trend.change, closeTo(90, tolerance));
      expect(trend.typical, closeTo(26.5, tolerance));
      expect(trend.centerDay, closeTo(26.5, tolerance));
      expect(
        trend.direction(RingLever.restingHeartRate),
        LeverDirection.rising,
      );
    });

    test('53 days give null', () {
      expect(theilSen(series(53, (x) => x.toDouble()), end: end), isNull);
    });

    test('no days give null', () {
      expect(theilSen(const [], end: end), isNull);
    });

    test('days outside the window are ignored', () {
      final days = [
        ...series(53, (x) => x.toDouble()),
        (date: end.addDays(1), value: 1.0),
        (date: end.addDays(-90), value: 1.0),
        (date: end.addDays(-200), value: 1.0),
      ];
      expect(theilSen(days, end: end), isNull);
    });

    test('the first and last day of the window both count', () {
      final days = [
        ...series(52, (x) => x.toDouble(), from: 1),
        (date: end.addDays(-89), value: 0.0),
        (date: end, value: 89.0),
      ];
      expect(trendOf(days).validDays, 54);
    });

    test('non finite values are ignored', () {
      final days = [
        ...series(53, (x) => x.toDouble()),
        (date: end.addDays(-36), value: double.nan),
        (date: end.addDays(-35), value: double.infinity),
        (date: end.addDays(-34), value: double.negativeInfinity),
      ];
      expect(theilSen(days, end: end), isNull);
    });

    test('a non finite value among 54 good days is dropped, not counted', () {
      final days = [
        ...series(54, (x) => x.toDouble()),
        (date: end.addDays(-30), value: double.nan),
      ];
      expect(trendOf(days).validDays, 54);
    });

    test('a window with unordered days gives the same trend', () {
      final days = series(90, (x) => 8150 + 12 * x + 150 * r(x));
      final shuffled = days.reversed.toList();
      expect(trendOf(shuffled).slopeLow, trendOf(days).slopeLow);
      expect(trendOf(shuffled).slopeHigh, trendOf(days).slopeHigh);
    });
  });

  group('6. the fan exists only for steps', () {
    final trend = trendOf(series(90, (x) => 10.0 * x));

    test('a rising series is rising on every lever', () {
      for (final lever in RingLever.values) {
        expect(trend.direction(lever), LeverDirection.rising);
      }
    });

    test('fan is null for every lever except steps', () {
      expect(trend.fan(RingLever.steps), isNotNull);
      expect(trend.fan(RingLever.sleepRegularity), isNull);
      expect(trend.fan(RingLever.restingHeartRate), isNull);
      expect(trend.fan(RingLever.sleepDuration), isNull);
    });
  });

  group('review focus: repeated date', () {
    test('the last value of a repeated date wins', () {
      final days = [
        ...series(54, (x) => x.toDouble()),
        (date: end.addDays(-89), value: 1000.0),
      ];
      final trend = trendOf(days);

      expect(trend.validDays, 54);
      expect(trend.typical, closeTo(27.5, tolerance));
    });

    test('the first of a repeated date is dropped when it comes first', () {
      final days = [
        (date: end.addDays(-89), value: 1000.0),
        ...series(54, (x) => x.toDouble()),
      ];
      final trend = trendOf(days);

      expect(trend.validDays, 54);
      expect(trend.typical, closeTo(26.5, tolerance));
    });

    test('a repeated date does not lift 53 days to the minimum', () {
      final days = [
        ...series(53, (x) => x.toDouble()),
        (date: end.addDays(-89), value: 5.0),
      ];
      expect(theilSen(days, end: end), isNull);
    });
  });

  group('review focus: ties in the values', () {
    test('tied values narrow sigma, so the upper bound is 0.024096', () {
      final trend = trendOf(series(90, (x) => 54 + r(x)));

      expect(trend.slopeLow, closeTo(-0.019230769230769232, tolerance));
      expect(trend.slopeHigh, closeTo(0.024096385542168676, tolerance));
      expect(trend.slopeHigh, isNot(closeTo(0.027777777777777776, 1e-6)));
    });

    test('an all equal series is flat with a zero width interval', () {
      final trend = trendOf(series(90, (x) => 7.0));

      expect(trend.slopePerDay, 0);
      expect(trend.slopeLow, 0);
      expect(trend.slopeHigh, 0);
      expect(trend.direction(RingLever.steps), LeverDirection.stable);
    });
  });

  group('review focus: change exactly equal to the minimum', () {
    test('a rise of exactly 500 steps over 90 days is rising', () {
      const slope = 500 / 90;
      final trend = trendOf(series(90, (x) => slope * x));

      expect(trend.change, 500);
      expect(trend.direction(RingLever.steps), LeverDirection.rising);
    });

    test('a fall of exactly 2 bpm over 90 days is falling', () {
      const slope = 2 / 90;
      final trend = trendOf(series(90, (x) => -(slope * x)));

      expect(trend.change, -2);
      expect(
        trend.direction(RingLever.restingHeartRate),
        LeverDirection.falling,
      );
    });

    test('a rise just under the minimum is stable', () {
      const slope = 499 / 90;
      final trend = trendOf(series(90, (x) => slope * x));

      expect(trend.direction(RingLever.steps), LeverDirection.stable);
    });

    test('direction on a hand built trend follows the rule', () {
      LeverTrend built(double low, double slope, double high) => LeverTrend(
        slopePerDay: slope,
        slopeLow: low,
        slopeHigh: high,
        typical: 100,
        centerDay: 44.5,
        validDays: 90,
      );

      expect(
        built(1, 10, 20).direction(RingLever.steps),
        LeverDirection.rising,
      );
      expect(
        built(0, 10, 20).direction(RingLever.steps),
        LeverDirection.stable,
      );
      expect(
        built(-20, -10, -1).direction(RingLever.steps),
        LeverDirection.falling,
      );
      expect(
        built(-20, -10, 0).direction(RingLever.steps),
        LeverDirection.stable,
      );
      expect(built(1, 4, 9).direction(RingLever.steps), LeverDirection.stable);
      expect(
        built(-9, -4, -1).direction(RingLever.steps),
        LeverDirection.stable,
      );
    });

    test('change and its interval are the slopes times 90', () {
      const trend = LeverTrend(
        slopePerDay: 2,
        slopeLow: 1,
        slopeHigh: 3,
        typical: 100,
        centerDay: 44.5,
        validDays: 90,
      );

      expect(trend.change, 180);
      expect(trend.changeLow, 90);
      expect(trend.changeHigh, 270);
    });
  });

  group('7. a valid step day', () {
    test('40 buckets of 15 minutes are valid', () {
      expect(isValidStepDay(quarterHours(40)), isTrue);
    });

    test('39 buckets of 15 minutes are not valid', () {
      expect(isValidStepDay(quarterHours(39)), isFalse);
    });

    test('no buckets are not valid', () {
      expect(isValidStepDay(const []), isFalse);
    });

    test('48 buckets with 8 inside sleep are valid', () {
      final sleep = [sleepSpan(0, 120)];
      expect(isValidStepDay(quarterHours(48), sleep: sleep), isTrue);
    });

    test('48 buckets with 9 inside sleep are not valid', () {
      final sleep = [sleepSpan(0, 135)];
      expect(isValidStepDay(quarterHours(48), sleep: sleep), isFalse);
    });

    test('a duplicated bucket counts once', () {
      final buckets = [...quarterHours(39), bucket(0)];
      expect(isValidStepDay(buckets), isFalse);
    });

    test('40 buckets with one duplicated are still valid', () {
      final buckets = [...quarterHours(40), bucket(0)];
      expect(isValidStepDay(buckets), isTrue);
    });

    test('a zero step bucket counts', () {
      expect(isValidStepDay(quarterHours(40, steps: 0)), isTrue);
    });
  });

  group('review focus: overlapping buckets and sleep clipping', () {
    List<StepBucket> halfHourEveryQuarter(int count) => [
      for (var i = 0; i < count; i++) bucket(i, minutes: 30),
    ];

    test(
      'overlapping buckets count their union, 39 cover exactly 10 hours',
      () {
        expect(isValidStepDay(halfHourEveryQuarter(39)), isTrue);
      },
    );

    test('38 overlapping buckets cover 9 hours 45 and are not valid', () {
      expect(isValidStepDay(halfHourEveryQuarter(38)), isFalse);
    });

    test('sleep clips part of a bucket, not the whole of it', () {
      final sleep = [sleepSpan(-10, 5)];
      expect(isValidStepDay(quarterHours(40), sleep: sleep), isFalse);
      expect(isValidStepDay(quarterHours(41), sleep: sleep), isTrue);
    });

    test('sleep inside a bucket removes only its own minutes', () {
      final sleep = [sleepSpan(10, 20)];
      expect(isValidStepDay(quarterHours(41), sleep: sleep), isTrue);
    });

    test('two overlapping sleep spans remove the same minutes once', () {
      final sleep = [sleepSpan(0, 15), sleepSpan(0, 15)];
      expect(isValidStepDay(quarterHours(41), sleep: sleep), isTrue);
    });

    test('sleep outside every bucket removes nothing', () {
      final sleep = [sleepSpan(-600, -300)];
      expect(isValidStepDay(quarterHours(40), sleep: sleep), isTrue);
    });

    test('a bucket that crosses midnight counts its full length', () {
      final midnight = DateTime.utc(2026, 11, 25);
      final crossing = <StepBucket>[
        for (var i = 0; i < 40; i++)
          (
            start: midnight.add(Duration(minutes: (i - 20) * 15)),
            duration: const Duration(minutes: 15),
            steps: 3,
          ),
      ];
      expect(isValidStepDay(crossing), isTrue);
    });
  });

  test('a bucket across midnight counts in full', () {
    final midnight = DateTime.utc(2026, 11, 25);
    final crossing = <StepBucket>[
      for (var i = 0; i < 40; i++)
        (
          start: midnight.add(Duration(minutes: (i - 20) * 15 + 7)),
          duration: const Duration(minutes: 15),
          steps: 3,
        ),
    ];
    expect(isValidStepDay(crossing), isTrue);
  });

  test('days are counted from the window start, not the first valid day', () {
    final trend = trendOf(series(54, (x) => 100 + 10.0 * x, from: 36));
    expect(trend.centerDay, closeTo(62.5, tolerance));
    final fan = trend.fan(RingLever.steps)!;
    expect(fan.low, closeTo(1890, tolerance));
    expect(fan.high, closeTo(1890, tolerance));
  });

  test('the interval is a sorted pair of slopes', () {
    final trend = trendOf(series(90, (x) => 100 * math.sin(x / 7)));

    expect(trend.slopeLow, lessThanOrEqualTo(trend.slopePerDay));
    expect(trend.slopePerDay, lessThanOrEqualTo(trend.slopeHigh));
  });
}
