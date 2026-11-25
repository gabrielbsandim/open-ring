import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const series0 = LocalDate(2026, 11, 16);
const today = LocalDate(2026, 12, 10);
const skipped = {-30, -22, -13, -4, 5, 12, 19};

const protoRate = WeightRateReady(
  perWeek: -0.348097,
  low: -0.434510,
  high: -0.261684,
);

double wobble(int d) => (((d + 35) * 7919 + 13) % 101 / 101 - 0.5) * 0.8;

double round1(double value) => (value * 10).round() / 10;

List<DailyValue> prototypeSeries(double slope) => [
  for (var d = -35; d <= 24; d++)
    if (!skipped.contains(d))
      (
        date: series0.addDays(d),
        value: round1(78.4 - (d > 0 ? slope * d : 0) + wobble(d)),
      ),
];

WeightRateReady ready(WeightRate rate) => rate as WeightRateReady;

LossRate lossOf(double slope) {
  final series = prototypeSeries(slope);
  final trend = weightTrend(series).last.value;
  return lossRate(ready(weightRate(series, today: today)), trend);
}

void main() {
  group('1. scenarioDays bends the elapsed days by the adaptation time', () {
    test('84 days is 75.035', () {
      expect(scenarioDays(84), closeTo(75.035, 0.001));
    });

    test('28 days is 26.953', () {
      expect(scenarioDays(28), closeTo(26.953, 0.001));
    });

    test('0 days is 0', () {
      expect(scenarioDays(0), 0);
    });

    test('the constants are the ones the spec names', () {
      expect(trajectoryAdaptationDays, 365.0);
      expect(trajectoryFirmDays, 28);
      expect(trajectoryBandDays, 84);
      expect(trajectoryFastLossPercent, 1.0);
    });
  });

  group('2. weightScenario reproduces the prototype band', () {
    test('84 days is 72.597, 73.873, 75.149', () {
      final band = weightScenario(77.60447, protoRate, 0.35, 84);
      expect(band.days, 84);
      expect(band.low, closeTo(72.597, 0.01));
      expect(band.mid, closeTo(73.873, 0.01));
      expect(band.high, closeTo(75.149, 0.01));
    });

    test('28 days is 75.581, 76.264, 76.947', () {
      final band = weightScenario(77.60447, protoRate, 0.35, 28);
      expect(band.days, 28);
      expect(band.low, closeTo(75.581, 0.01));
      expect(band.mid, closeTo(76.264, 0.01));
      expect(band.high, closeTo(76.947, 0.01));
    });

    test('a rising weight bends the same way, upward', () {
      const rising = WeightRateReady(perWeek: 0.3, low: 0.1, high: 0.5);
      final band = weightScenario(80, rising, 0.4, 84);
      final bend = scenarioDays(84) / 7;
      expect(band.mid, closeTo(80 + 0.3 * bend, 1e-9));
      expect(band.low, closeTo(80 + 0.1 * bend - 0.4, 1e-9));
      expect(band.high, closeTo(80 + 0.5 * bend + 0.4, 1e-9));
    });

    test('the noise is added outside both edges, not to the middle', () {
      final quiet = weightScenario(77.6, protoRate, 0, 84);
      final noisy = weightScenario(77.6, protoRate, 0.5, 84);
      expect(noisy.mid, closeTo(quiet.mid, 1e-9));
      expect(noisy.low, closeTo(quiet.low - 0.5, 1e-9));
      expect(noisy.high, closeTo(quiet.high + 0.5, 1e-9));
    });
  });

  group('3. the prototype series end to end', () {
    test('the series has 25 weigh-ins in the 28 day rate window', () {
      final inWindow = [
        for (final day in prototypeSeries(0.05))
          if (today.daysSince(day.date) < weightRateWindowDays) day,
      ];
      expect(inWindow, hasLength(25));
    });

    test('through the existing APIs the 84 day band is 72.6 to 75.1', () {
      final series = prototypeSeries(0.05);
      final trend = weightTrend(series).last.value;
      final rate = ready(weightRate(series, today: today));
      final noise = weightNoise(series);
      expect(trend, closeTo(77.60447, 0.001));
      expect(rate.perWeek, closeTo(-0.348097, 0.001));
      expect(noise, closeTo(0.35, 1e-9));
      final band = weightScenario(trend, rate, noise, trajectoryBandDays);
      expect(band.low.toStringAsFixed(1), '72.6');
      expect(band.high.toStringAsFixed(1), '75.1');
    });
  });

  group('4. the fast loss guard on the same series', () {
    test('slope 0.16 reads 1.30 to 1.56 percent and trips the guard', () {
      final loss = lossOf(0.16);
      expect(loss.percentLow, closeTo(1.30, 0.005));
      expect(loss.percentHigh, closeTo(1.56, 0.005));
      expect(fastLossGuard(loss), isTrue);
    });

    test('slope 0.05 does not trip the guard', () {
      expect(fastLossGuard(lossOf(0.05)), isFalse);
    });

    test('slope 0 does not trip the guard', () {
      expect(fastLossGuard(lossOf(0)), isFalse);
    });
  });

  group('5. the guard is strict at the cap', () {
    LossRate atPercentLow(double percentLow) => LossRate(
      kg: 1,
      kgLow: 1,
      kgHigh: 1,
      percent: 1,
      percentLow: percentLow,
      percentHigh: 2,
    );

    test('percentLow exactly 1.0 is false', () {
      expect(fastLossGuard(atPercentLow(1)), isFalse);
    });

    test('percentLow just above 1.0 is true', () {
      expect(fastLossGuard(atPercentLow(1.0001)), isTrue);
    });

    test('the guard reads percentLow, not the middle or the high edge', () {
      const lowEdgeBelow = LossRate(
        kg: 1,
        kgLow: 1,
        kgHigh: 1,
        percent: 1.5,
        percentLow: 0.9,
        percentHigh: 2,
      );
      expect(fastLossGuard(lowEdgeBelow), isFalse);
    });
  });

  group('6. a flat weight still has a band', () {
    test('slope 0 at 84 days has low below trend below high', () {
      const flat = WeightRateReady(perWeek: 0, low: -0.1, high: 0.1);
      final band = weightScenario(78, flat, 0.35, 84);
      expect(band.low, lessThan(78));
      expect(band.high, greaterThan(78));
      expect(band.mid, closeTo(78, 1e-9));
    });

    test('the zero rate of the prototype series spans its trend', () {
      final series = prototypeSeries(0);
      final trend = weightTrend(series).last.value;
      final rate = ready(weightRate(series, today: today));
      final band = weightScenario(
        trend,
        rate,
        weightNoise(series),
        trajectoryBandDays,
      );
      expect(band.low, lessThan(trend));
      expect(band.high, greaterThan(trend));
    });
  });

  group('7. the edges of the input', () {
    test('0 days is the trend, with the noise on both sides', () {
      final band = weightScenario(77.6, protoRate, 0.35, 0);
      expect(band.days, 0);
      expect(band.mid, closeTo(77.6, 1e-9));
      expect(band.low, closeTo(77.25, 1e-9));
      expect(band.high, closeTo(77.95, 1e-9));
    });

    test('negative days throw ArgumentError', () {
      expect(
        () => weightScenario(77.6, protoRate, 0.35, -1),
        throwsArgumentError,
      );
    });

    test('negative noise throws ArgumentError', () {
      expect(
        () => weightScenario(77.6, protoRate, -0.01, 84),
        throwsArgumentError,
      );
    });

    test('one day bends to just under one day', () {
      expect(scenarioDays(1), closeTo(0.9986, 0.0001));
    });
  });
}
