import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const _floor160 = 47.36;

ScenarioBand _band(double low, double mid, double high) =>
    ScenarioBand(days: 84, low: low, mid: mid, high: high);

void main() {
  group('1. a falling band is lifted to the BMI 18.5 weight', () {
    test('160 cm and trend 48 lifts every edge below 47.36 to 47.36', () {
      final floored = scenarioFloored(
        _band(44, 46, 47.1),
        trendKg: 48,
        heightCm: 160,
      );

      expect(floored.low, closeTo(_floor160, 1e-9));
      expect(floored.mid, closeTo(_floor160, 1e-9));
      expect(floored.high, closeTo(_floor160, 1e-9));
      expect(floored.days, 84);
    });

    test('edges above the floor stay as they were', () {
      final floored = scenarioFloored(
        _band(44, 47.5, 49),
        trendKg: 48,
        heightCm: 160,
      );

      expect(floored.low, closeTo(_floor160, 1e-9));
      expect(floored.mid, 47.5);
      expect(floored.high, 49);
    });

    test('an edge exactly on the floor is unchanged', () {
      final floored = scenarioFloored(
        _band(_floor160, 48, 49),
        trendKg: 48,
        heightCm: 160,
      );

      expect(floored.low, closeTo(_floor160, 1e-9));
      expect(floored.mid, 48);
    });
  });

  group('2. a trend already under the floor stops the floor at the trend', () {
    test('160 cm and trend 46 gives every edge at least 46', () {
      final floored = scenarioFloored(
        _band(40, 44, 45.5),
        trendKg: 46,
        heightCm: 160,
      );

      expect(floored.low, 46);
      expect(floored.mid, 46);
      expect(floored.high, 46);
    });

    test('no edge is pushed above max of itself and 46', () {
      final floored = scenarioFloored(
        _band(40, 46.5, 50),
        trendKg: 46,
        heightCm: 160,
      );

      expect(floored.low, 46);
      expect(floored.mid, 46.5);
      expect(floored.high, 50);
    });
  });

  group('3. a band entirely above the floor is returned unchanged', () {
    test('equal values and days', () {
      final floored = scenarioFloored(
        _band(70, 72, 74),
        trendKg: 73,
        heightCm: 160,
      );

      expect(floored.days, 84);
      expect(floored.low, 70);
      expect(floored.mid, 72);
      expect(floored.high, 74);
    });
  });

  group('5. a tiny height leaves the band alone', () {
    test('1 cm has a floor far under every edge', () {
      final floored = scenarioFloored(
        _band(70, 72, 74),
        trendKg: 73,
        heightCm: 1,
      );

      expect(floored.low, 70);
      expect(floored.mid, 72);
      expect(floored.high, 74);
    });

    test('the floor never lowers an edge', () {
      final floored = scenarioFloored(
        _band(0.5, 0.6, 0.7),
        trendKg: 0.6,
        heightCm: 1,
      );

      expect(floored.low, 0.5);
      expect(floored.mid, 0.6);
      expect(floored.high, 0.7);
    });
  });
}
