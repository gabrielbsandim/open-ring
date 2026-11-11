import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

List<StressReading> slots(List<int> levels) => [
  for (var i = 0; i < levels.length; i++)
    (
      at: DateTime.utc(2026, 11, 10).add(Duration(minutes: 30 * i)),
      level: levels[i],
    ),
];

void main() {
  test('bands split at 25, 50 and 75', () {
    expect(stressBandOf(1), StressBand.rest);
    expect(stressBandOf(25), StressBand.rest);
    expect(stressBandOf(26), StressBand.low);
    expect(stressBandOf(50), StressBand.low);
    expect(stressBandOf(51), StressBand.medium);
    expect(stressBandOf(75), StressBand.medium);
    expect(stressBandOf(76), StressBand.high);
    expect(stressBandOf(100), StressBand.high);
  });

  test('a day summarises mean, range and time per band', () {
    final summary = stressDaySummary(
      slots([10, 25, 26, 50, 51, 75, 76, 100, 0, 101]),
    )!;
    expect(summary.readings, 8);
    expect(summary.mean, closeTo(413 / 8, 1e-12));
    expect(summary.min, 10);
    expect(summary.max, 100);
    for (final band in StressBand.values) {
      expect(summary.timeInBand[band], const Duration(hours: 1));
    }
    expect(summary.measured, const Duration(hours: 4));
  });

  test('needs three readings by default', () {
    expect(stressDaySummary(const []), isNull);
    expect(stressDaySummary(slots([0, 0, 0, 0])), isNull);
    expect(stressDaySummary(slots([40])), isNull);
    final one = stressDaySummary(slots([40]), minReadings: 1)!;
    expect(one.mean, 40);
    expect(one.min, one.max);
    expect(one.timeInBand[StressBand.low], stressSlot);
  });

  test('honours a custom slot and rejects bad settings', () {
    final summary = stressDaySummary(
      slots([80, 90, 95]),
      slot: const Duration(minutes: 5),
    )!;
    expect(summary.timeInBand[StressBand.high], const Duration(minutes: 15));
    expect(summary.timeInBand[StressBand.rest], Duration.zero);
    expect(
      () => stressDaySummary(const [], slot: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => stressDaySummary(const [], minReadings: 0),
      throwsArgumentError,
    );
  });
}
