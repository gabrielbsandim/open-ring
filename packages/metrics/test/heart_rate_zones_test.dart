import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

final start = DateTime.utc(2026, 11, 10, 7);

BpmSample s(int seconds, int bpm) =>
    (at: start.add(Duration(seconds: seconds)), bpm: bpm);

void main() {
  test('max HR defaults to 220 minus age', () {
    expect(maxHeartRateForAge(30), 190);
    expect(maxHeartRateForAge(1), 219);
    expect(maxHeartRateForAge(119), 101);
    expect(() => maxHeartRateForAge(0), throwsArgumentError);
    expect(() => maxHeartRateForAge(120), throwsArgumentError);
  });

  test('five zones start at 50, 60, 70, 80 and 90 percent of max', () {
    final zones = HeartRateZones(age: 30);
    expect(zones.maxHeartRate, 190);
    expect(zones.zones.map((z) => z.lowerBpm), [95, 114, 133, 152, 171]);
    expect(zones.zones.map((z) => z.upperBpm), [114, 133, 152, 171, null]);
    expect(zones.zones.map((z) => z.number), [1, 2, 3, 4, 5]);
  });

  test('an explicit max HR overrides the age formula', () {
    final zones = HeartRateZones(age: 30, maxHeartRate: 200);
    expect(zones.maxHeartRate, 200);
    expect(zones.zones.first.lowerBpm, 100);
    expect(zones.zones.last.lowerBpm, 180);
  });

  test('zone boundaries: lower bound in, upper bound out', () {
    final zones = HeartRateZones(maxHeartRate: 200);
    expect(zones.zoneOf(0), isNull);
    expect(zones.zoneOf(99), isNull);
    expect(zones.zoneOf(100), 1);
    expect(zones.zoneOf(119), 1);
    expect(zones.zoneOf(120), 2);
    expect(zones.zoneOf(179), 4);
    expect(zones.zoneOf(180), 5);
    expect(zones.zoneOf(200), 5);
    expect(zones.zoneOf(230), 5);
  });

  test('rejects no input and implausible max HR', () {
    expect(HeartRateZones.new, throwsArgumentError);
    expect(() => HeartRateZones(maxHeartRate: 99), throwsArgumentError);
    expect(() => HeartRateZones(maxHeartRate: 251), throwsArgumentError);
    expect(HeartRateZones(maxHeartRate: 100).zones.first.lowerBpm, 50);
    expect(HeartRateZones(maxHeartRate: 250).zones.last.lowerBpm, 225);
  });

  group('timeInZones', () {
    final zones = HeartRateZones(maxHeartRate: 200);

    test('each sample counts until the next one, capped at maxHold', () {
      final totals = zones.timeInZones([
        s(0, 110),
        s(1, 110),
        s(2, 125),
        s(3, 0),
        s(4, 185),
        s(64, 185),
        s(65, 90),
        s(66, 150),
      ]);
      expect(totals[1], const Duration(seconds: 2));
      expect(totals[2], const Duration(seconds: 2));
      expect(totals[3], Duration.zero);
      expect(totals[5], const Duration(seconds: 11));
      expect(totals.keys, [1, 2, 3, 4, 5]);
    });

    test('no samples or a single sample add no time', () {
      expect(zones.timeInZones(const []).values.toSet(), {Duration.zero});
      expect(zones.timeInZones([s(0, 150)]).values.toSet(), {Duration.zero});
    });

    test('sorts samples and honours a custom maxHold', () {
      final totals = zones.timeInZones([
        s(30, 150),
        s(0, 150),
      ], maxHold: const Duration(minutes: 1));
      expect(totals[3], const Duration(seconds: 30));
    });
  });
}
