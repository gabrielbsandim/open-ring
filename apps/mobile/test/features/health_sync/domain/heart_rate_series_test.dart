import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/health_sync/domain/batch_plan.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/domain/heart_rate_series.dart';

final DateTime hour = DateTime.utc(2026, 11, 10, 14).toLocal();

DateTime minute(int m) => hour.add(Duration(minutes: m));

HeartRateEntry beat(int m, [int bpm = 70]) =>
    HeartRateEntry(id: 'hr-$m', at: minute(m), bpm: bpm);

List<int> minutesOf(HeartRateSeriesEntry series) => [
  for (final sample in series.samples) sample.at.difference(hour).inMinutes,
];

void main() {
  test('samples group by UTC hour, spanning first to last sample', () {
    final series = heartRateSeries('ring', [
      beat(70),
      beat(0),
      beat(5),
      beat(55),
      beat(60),
    ]);

    expect(series.map(minutesOf), [
      [0, 5, 55],
      [60, 70],
    ]);
    expect(series.first.start, minute(0));
    expect(series.first.end, minute(55));
    expect(
      series.first.id,
      HealthRecordId.of('ring', HealthEntryType.heartRateSeries, minute(0)),
    );
  });

  test('the same samples make the same records whatever came first', () {
    final all = [for (var m = 0; m < 120; m += 5) beat(m)];

    final once = heartRateSeries('ring', all);
    final reversed = heartRateSeries('ring', all.reversed);

    expect(reversed, once);
    expect(once, hasLength(2));
  });

  test('an excluded window drops its samples and splits the hour', () {
    final series = heartRateSeries(
      'ring',
      [for (var m = 0; m < 60; m += 5) beat(m)],
      excluded: [TimeWindow(minute(12), minute(31))],
    );

    expect(series.map(minutesOf), [
      [0, 5, 10],
      [35, 40, 45, 50, 55],
    ]);
  });

  test('a window between two samples splits even with none inside', () {
    final series = heartRateSeries(
      'ring',
      [beat(0), beat(5)],
      excluded: [TimeWindow(minute(1), minute(3))],
    );

    expect(series, hasLength(2));
  });

  test('a series never holds more than the sample cap', () {
    final series = heartRateSeries('ring', [
      for (var m = 0; m < 7; m++) beat(m),
    ], maxSamples: 3);

    expect(series.map((s) => s.samples.length), [3, 3, 1]);
    expect(series.map((s) => s.id).toSet(), hasLength(3));
  });

  test('a workout is one series spanning the whole session', () {
    final series = workoutHeartRateSeries(
      'phone',
      start: minute(0),
      end: minute(105),
      samples: [beat(90), beat(1), beat(45)],
    );

    final only = series.single;
    expect(only.start, minute(0));
    expect(only.end, minute(105));
    expect(minutesOf(only), [1, 45, 90]);
    expect(
      only.id,
      HealthRecordId.of(
        'phone',
        HealthEntryType.workoutHeartRateSeries,
        minute(0),
      ),
    );
  });

  test('a workout past the sample cap splits and still covers the session', () {
    final series = workoutHeartRateSeries(
      'phone',
      start: minute(0),
      end: minute(10),
      samples: [for (var m = 1; m < 10; m++) beat(m)],
      maxSamples: 4,
    );

    expect(series.map(minutesOf), [
      [1, 2, 3, 4],
      [5, 6, 7, 8],
      [9],
    ]);
    expect(series.map((s) => (s.start, s.end)), [
      (minute(0), minute(4)),
      (minute(5), minute(8)),
      (minute(9), minute(10)),
    ]);
  });

  test('a workout without samples has no series', () {
    expect(
      workoutHeartRateSeries(
        'phone',
        start: minute(0),
        end: minute(10),
        samples: const [],
      ),
      isEmpty,
    );
  });
}
