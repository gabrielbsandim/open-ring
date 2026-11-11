import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

final from = DateTime.utc(2026, 11, 10, 2);
final to = DateTime.utc(2026, 11, 10, 9);

Spo2Reading at(int hour, int percent) =>
    (at: DateTime.utc(2026, 11, 10, hour), percent: percent);

void main() {
  test('a night summarises min, mean and time below 90 percent', () {
    final summary = spo2NightSummary(
      [
        at(1, 70),
        at(2, 97),
        at(3, 89),
        at(4, 90),
        at(5, 0),
        at(6, 65),
        at(7, 95),
        at(8, 88),
        at(9, 70),
      ],
      from: from,
      to: to,
    )!;
    expect(summary.readings, 5);
    expect(summary.min, 88);
    expect(summary.mean, closeTo(459 / 5, 1e-12));
    expect(summary.readingsBelow, 2);
    expect(summary.timeBelow, const Duration(hours: 2));
    expect(summary.shareBelow, closeTo(0.4, 1e-12));
  });

  test('a night with every reading at 90 has no time below', () {
    final summary = spo2NightSummary(
      [at(2, 90), at(3, 90), at(4, 90)],
      from: from,
      to: to,
    )!;
    expect(summary.timeBelow, Duration.zero);
    expect(summary.min, 90);
  });

  test('needs three plausible readings by default', () {
    expect(spo2NightSummary(const [], from: from, to: to), isNull);
    expect(spo2NightSummary([at(3, 89)], from: from, to: to), isNull);
    final one = spo2NightSummary(
      [at(3, 89)],
      from: from,
      to: to,
      minReadings: 1,
      sampleInterval: const Duration(minutes: 10),
    )!;
    expect(one.min, 89);
    expect(one.timeBelow, const Duration(minutes: 10));
    expect(one.shareBelow, 1);
  });

  test('rejects an empty window and bad settings', () {
    expect(
      () => spo2NightSummary(const [], from: to, to: from),
      throwsArgumentError,
    );
    expect(
      () => spo2NightSummary(const [], from: from, to: from),
      throwsArgumentError,
    );
    expect(
      () => spo2NightSummary(
        const [],
        from: from,
        to: to,
        sampleInterval: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(
      () => spo2NightSummary(const [], from: from, to: to, minReadings: 0),
      throwsArgumentError,
    );
  });
}
