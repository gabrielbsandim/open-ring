import 'dart:math' as math;

import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const today = LocalDate(2026, 11, 10);

List<DailyValue> daysBefore(List<double> values, {int startAgo = 1}) => [
  for (var i = 0; i < values.length; i++)
    (date: today.addDays(-(startAgo + i)), value: values[i]),
];

BaselineReady ready(BaselineResult result) => result as BaselineReady;

void main() {
  group('minimum data', () {
    test('no history is still building', () {
      final result = personalBaseline(const [], today: today);
      expect(result, isA<BaselineBuilding>());
      expect((result as BaselineBuilding).daysCollected, 0);
      expect(result.daysNeeded, baselineMinDays);
    });

    test('six days is building, seven is ready', () {
      final six = personalBaseline(
        daysBefore(List.filled(6, 60)),
        today: today,
      );
      expect((six as BaselineBuilding).daysCollected, 6);
      final seven = personalBaseline(
        daysBefore(List.filled(7, 60)),
        today: today,
      );
      expect(ready(seven).days, 7);
    });

    test('a single reading cannot make a baseline', () {
      final result = personalBaseline(daysBefore([60]), today: today);
      expect((result as BaselineBuilding).daysCollected, 1);
    });
  });

  group('window', () {
    test('excludes today and anything older than the window', () {
      final history = [
        (date: today, value: 200.0),
        ...daysBefore(List.filled(7, 60)),
        (date: today.addDays(-28), value: 66.0),
        (date: today.addDays(-29), value: 500.0),
        (date: today.addDays(1), value: 500.0),
      ];
      final result = ready(personalBaseline(history, today: today));
      expect(result.days, 8);
      expect(result.typical, closeTo((7 * 60 + 66) / 8, 1e-9));
    });

    test('keeps one value per date, the last one given', () {
      final history = [
        ...daysBefore(List.filled(7, 60)),
        (date: today.addDays(-1), value: 67.0),
      ];
      final result = ready(personalBaseline(history, today: today));
      expect(result.days, 7);
      expect(result.typical, closeTo((6 * 60 + 67) / 7, 1e-9));
    });

    test('rejects nonsense window settings', () {
      expect(
        () => personalBaseline(const [], today: today, windowDays: 0),
        throwsArgumentError,
      );
      expect(
        () => personalBaseline(const [], today: today, minDays: 1),
        throwsArgumentError,
      );
      expect(
        () => personalBaseline(const [], today: today, windowDays: 5),
        throwsArgumentError,
      );
    });
  });

  group('resting heart rate', () {
    test('mean, sample SD and z score on the bpm scale', () {
      final result = ready(
        restingHeartRateBaseline(
          daysBefore([60, 62, 58, 60, 61, 59, 60]),
          today: today,
        ),
      );
      expect(result.typical, closeTo(60, 1e-9));
      expect(result.sdOnScale, closeTo(math.sqrt(10 / 6), 1e-9));
      final deviation = result.compare(64);
      expect(deviation.delta, closeTo(4, 1e-9));
      expect(deviation.percent, closeTo(100 * 4 / 60, 1e-9));
      expect(deviation.zScore, closeTo(4 / math.sqrt(10 / 6), 1e-9));
    });

    test('a flat history uses the 1 bpm spread floor', () {
      final result = ready(
        restingHeartRateBaseline(daysBefore(List.filled(10, 55)), today: today),
      );
      expect(result.sdOnScale, restingHeartRateMinSpread);
      expect(result.compare(57).zScore, closeTo(2, 1e-9));
    });

    test('ignores values that are not finite', () {
      final result = restingHeartRateBaseline([
        ...daysBefore(List.filled(6, 55)),
        (date: today.addDays(-7), value: double.nan),
      ], today: today);
      expect((result as BaselineBuilding).daysCollected, 6);
    });
  });

  group('HRV', () {
    test('works on ln values and reports the geometric mean', () {
      final values = <double>[30, 40, 50, 35, 45, 42, 38];
      final result = ready(hrvBaseline(daysBefore(values), today: today));
      final logs = values.map(math.log).toList();
      final mean = logs.reduce((a, b) => a + b) / logs.length;
      expect(result.scale, BaselineScale.log);
      expect(result.meanOnScale, closeTo(mean, 1e-12));
      expect(result.typical, closeTo(math.exp(mean), 1e-9));
      final deviation = result.compare(30);
      expect(
        deviation.zScore,
        closeTo((math.log(30) - mean) / result.sdOnScale, 1e-9),
      );
      expect(deviation.zScore, isNegative);
      expect(deviation.percent, closeTo((30 / math.exp(mean) - 1) * 100, 1e-9));
    });

    test('a flat history uses the 0.05 ln spread floor', () {
      final result = ready(
        hrvBaseline(daysBefore(List.filled(7, 40)), today: today),
      );
      expect(result.sdOnScale, hrvMinLogSpread);
      expect(result.compare(40 * math.exp(-0.1)).zScore, closeTo(-2, 1e-9));
    });

    test(
      'skips zero and negative nights, and rejects a non positive today',
      () {
        final result = hrvBaseline([
          ...daysBefore(List.filled(6, 40)),
          (date: today.addDays(-7), value: 0),
          (date: today.addDays(-8), value: -3),
        ], today: today);
        expect((result as BaselineBuilding).daysCollected, 6);
        final built = ready(
          hrvBaseline(daysBefore(List.filled(7, 40)), today: today),
        );
        expect(() => built.compare(0), throwsArgumentError);
      },
    );
  });

  group('nightlyHrv', () {
    DateTime at(int slot) =>
        DateTime.utc(2026, 11, 10, 3).add(Duration(minutes: 30 * slot));

    test('averages the valid slots of the night', () {
      final readings = [
        (at: at(0), milliseconds: 40),
        (at: at(1), milliseconds: 0),
        (at: at(2), milliseconds: 50),
        (at: at(3), milliseconds: 45),
      ];
      expect(nightlyHrv(readings), closeTo(45, 1e-9));
    });

    test('needs three readings by default', () {
      expect(nightlyHrv(const []), isNull);
      final one = [(at: at(0), milliseconds: 40)];
      expect(nightlyHrv(one), isNull);
      expect(nightlyHrv(one, minReadings: 1), 40);
      expect(() => nightlyHrv(one, minReadings: 0), throwsArgumentError);
    });
  });
}
