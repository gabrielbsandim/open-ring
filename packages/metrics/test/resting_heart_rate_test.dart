import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

final night = DateTime.utc(2026, 11, 10);

List<BpmSample> everyFiveMinutes(List<int> bpms, {DateTime? from}) => [
  for (var i = 0; i < bpms.length; i++)
    (at: (from ?? night).add(Duration(minutes: 5 * i)), bpm: bpms[i]),
];

void main() {
  test('returns null without samples', () {
    expect(restingHeartRate(const []), isNull);
  });

  test('a flat series rests at its only value', () {
    expect(restingHeartRate(everyFiveMinutes(List.filled(12, 58))), 58);
  });

  test('picks the lowest 30 minute mean, not the lowest single reading', () {
    final samples = everyFiveMinutes([
      ...[70, 70, 40, 70, 70, 70],
      ...[52, 54, 56, 54, 52, 56],
      ...[90, 90, 90, 90, 90, 90],
    ]);
    expect(restingHeartRate(samples), closeTo(54, 1e-9));
  });

  test('ignores zero readings the ring logs for missed slots', () {
    final samples = everyFiveMinutes([0, 60, 0, 62, 0, 64]);
    expect(restingHeartRate(samples), closeTo(62, 1e-9));
  });

  test('skips windows with fewer samples than minSamples', () {
    final samples = [
      ...everyFiveMinutes([70, 72, 74]),
      (at: night.add(const Duration(hours: 3)), bpm: 45),
    ];
    expect(restingHeartRate(samples), closeTo(72, 1e-9));
    expect(restingHeartRate(samples, minSamples: 1), 45);
  });

  test('sorts unordered input before windowing', () {
    final ordered = everyFiveMinutes([66, 64, 62, 60, 58, 56, 80, 80]);
    final shuffled = [...ordered.reversed];
    expect(restingHeartRate(shuffled), restingHeartRate(ordered));
  });

  test(
    'a window ends before its limit, so a sample 30 minutes later is out',
    () {
      final samples = [
        (at: night, bpm: 50),
        (at: night.add(const Duration(minutes: 30)), bpm: 100),
      ];
      expect(restingHeartRate(samples, minSamples: 1), 50);
      expect(restingHeartRate(samples, minSamples: 2), isNull);
    },
  );

  test('rejects a non positive window or minSamples', () {
    expect(
      () => restingHeartRate(const [], window: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => restingHeartRate(const [], minSamples: 0),
      throwsArgumentError,
    );
  });
}
