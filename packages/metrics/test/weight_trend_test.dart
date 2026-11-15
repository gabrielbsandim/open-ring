import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const start = LocalDate(2026, 10, 1);

List<DailyValue> onDays(Map<int, double> byDay) => [
  for (final entry in byDay.entries)
    (date: start.addDays(entry.key), value: entry.value),
];

List<DailyValue> everyOtherDay(List<double> values) => [
  for (var i = 0; i < values.length; i++)
    (date: start.addDays(2 * i), value: values[i]),
];

const wobble = [0.3, -0.3, 0.3, -0.3, -0.3, 0.3, -0.3, 0.3];

WeightRateReady ready(WeightRate rate) => rate as WeightRateReady;

WeightRateBuilding building(WeightRate rate) => rate as WeightRateBuilding;

void main() {
  group('dailyWeights', () {
    test('a date with several weigh-ins is their mean', () {
      final daily = dailyWeights([
        (date: start, value: 80),
        (date: start, value: 81),
        (date: start.addDays(1), value: 79),
      ]);
      expect(daily, hasLength(2));
      expect(daily.first.value, closeTo(80.5, 1e-9));
      expect(daily.last.value, 79);
    });

    test('dates come back oldest first', () {
      final daily = dailyWeights(onDays({5: 80, 0: 81, 2: 82}));
      expect([for (final d in daily) d.value], [81, 82, 80]);
    });

    test('a value that is not finite is dropped', () {
      final daily = dailyWeights(
        onDays({0: double.nan, 1: 80, 2: double.infinity}),
      );
      expect(daily, hasLength(1));
      expect(daily.single.date, start.addDays(1));
    });
  });

  group('weightTrend', () {
    test('no weigh-ins give no trend', () {
      expect(weightTrend(const []), isEmpty);
    });

    test('one weigh-in is its own trend', () {
      final trend = weightTrend(onDays({0: 80}));
      expect(trend.single.value, 80);
      expect(trend.single.date, start);
    });

    test('the trend starts at the mean of the first dates, seven at most', () {
      final short = weightTrend(onDays({0: 80, 1: 82, 2: 78, 3: 81}));
      expect(short.first.value, closeTo(80.25, 1e-9));
      final long = weightTrend(
        onDays({for (var i = 0; i < 9; i++) i: 70.0 + i}),
      );
      expect(long.first.value, closeTo(73, 1e-9));
    });

    test('each date moves a tenth of the way to its weight', () {
      final trend = weightTrend(onDays({0: 80, 1: 82, 2: 78, 3: 81}));
      expect(
        [for (final t in trend) t.value],
        [
          closeTo(80.25, 1e-9),
          closeTo(80.425, 1e-9),
          closeTo(80.1825, 1e-9),
          closeTo(80.26425, 1e-9),
        ],
      );
    });

    test('a gap of two days pulls as two days would', () {
      final trend = weightTrend(onDays({0: 80, 2: 82}));
      expect(trend.last.value, closeTo(81.19, 1e-9));
    });

    test('a steady weight has a flat trend', () {
      final trend = weightTrend(onDays({for (var i = 0; i < 12; i++) i: 77.7}));
      for (final t in trend) {
        expect(t.value, closeTo(77.7, 1e-9));
      }
    });
  });

  group('weightRate', () {
    final today = start.addDays(14);

    test('no weigh-ins need eight dates and fourteen days', () {
      final rate = building(weightRate(const [], today: today));
      expect(rate.daysMissing, weightRateMinDays);
      expect(rate.spanMissing, weightRateMinSpanDays);
    });

    test('seven dates over fourteen days need one more date', () {
      final rate = building(
        weightRate(
          onDays({0: 80, 2: 80, 4: 80, 6: 80, 8: 80, 10: 80, 14: 80}),
          today: today,
        ),
      );
      expect(rate.daysMissing, 1);
      expect(rate.spanMissing, 0);
    });

    test('eight dates over thirteen days need one more day', () {
      final rate = building(
        weightRate(
          onDays({for (var i = 0; i < 7; i++) i: 80, 13: 80}),
          today: today,
        ),
      );
      expect(rate.daysMissing, 0);
      expect(rate.spanMissing, 1);
    });

    test('noise around a flat weight is stable', () {
      final rate = ready(
        weightRate(
          everyOtherDay([for (final w in wobble) 80 + w]),
          today: today,
        ),
      );
      expect(rate.perWeek, closeTo(0, 1e-9));
      expect(rate.low, closeTo(-0.45779, 1e-4));
      expect(rate.high, closeTo(0.45779, 1e-4));
      expect(rate.stable, isTrue);
    });

    test('a loss larger than the noise is not stable', () {
      final rate = ready(
        weightRate(
          everyOtherDay([
            for (var i = 0; i < wobble.length; i++) 80 - 0.2 * i + wobble[i],
          ]),
          today: today,
        ),
      );
      expect(rate.perWeek, closeTo(-0.7, 1e-9));
      expect(rate.low, closeTo(-1.15779, 1e-4));
      expect(rate.high, closeTo(-0.24221, 1e-4));
      expect(rate.stable, isFalse);
    });

    test('a full window uses the quantile for twenty six', () {
      final rate = ready(
        weightRate(
          onDays({
            for (var i = 0; i < 28; i++)
              i: 80 - 0.05 * i + (i.isEven ? 0.4 : -0.4),
          }),
          today: start.addDays(27),
        ),
      );
      expect(rate.perWeek, closeTo(-0.37146, 1e-4));
      expect(rate.low, closeTo(-0.51095, 1e-4));
      expect(rate.high, closeTo(-0.23196, 1e-4));
    });

    test('a perfect line has no interval', () {
      final rate = ready(
        weightRate(
          everyOtherDay([for (var i = 0; i < 8; i++) 80 - 0.1 * i]),
          today: today,
        ),
      );
      expect(rate.perWeek, closeTo(-0.35, 1e-9));
      expect(rate.high - rate.low, closeTo(0, 1e-9));
      expect(rate.stable, isFalse);
    });

    test('dates older than the window and dates after today are left out', () {
      final inside = everyOtherDay([for (final w in wobble) 80 + w]);
      final rate = ready(
        weightRate([
          ...inside,
          (date: today.addDays(-28), value: 120),
          (date: today.addDays(1), value: 40),
        ], today: today),
      );
      expect(rate.perWeek, closeTo(0, 1e-9));
    });

    test('the oldest date of the window is twenty seven days back', () {
      final rate = building(
        weightRate([
          (date: today.addDays(-27), value: 80),
          (date: today.addDays(-28), value: 80),
          (date: today, value: 80),
        ], today: today),
      );
      expect(rate.daysMissing, weightRateMinDays - 2);
      expect(rate.spanMissing, 0);
    });
  });

  group('weightNoise', () {
    test('fewer than three dates use the default', () {
      expect(weightNoise(const []), weightNoiseDefault);
      expect(weightNoise(onDays({0: 80, 1: 85})), weightNoiseDefault);
    });

    test('a quiet series stops at the floor', () {
      expect(weightNoise(onDays({0: 80, 1: 80.2, 2: 79.9})), weightNoiseFloor);
    });

    test('a noisy series is the root mean square around the trend', () {
      expect(
        weightNoise(onDays({0: 80, 1: 82, 2: 78, 3: 81})),
        closeTo(1.40069, 1e-4),
      );
    });
  });
}
