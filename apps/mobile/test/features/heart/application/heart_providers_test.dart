import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';

import '../../../helpers/metrics_fakes.dart';

ProviderContainer containerFor(MetricsScenario scenario) =>
    ProviderContainer.test(overrides: scenario.overrides());

// An overnight HR log: high at bedtime, a trough around 03:00, a rise toward
// waking, with every seventh slot missed as a loose ring does.
List<BpmSample> overnightHeartRate(LocalDate date, Duration every) {
  final start = nightStart(date);
  final samples = <BpmSample>[];
  for (var i = 0; start.add(every * i).isBefore(start.add(_nightLength)); i++) {
    if (i % 7 == 6) continue;
    final at = start.add(every * i);
    final hours = at.difference(start).inMinutes / 60;
    samples.add((at: at, bpm: (52 + 3 * (hours - 3.7).abs()).round()));
  }
  return samples;
}

const _nightLength = Duration(hours: 7, minutes: 44);

ProviderContainer firstSync({required int nights, required Duration every}) {
  final dates = [
    for (var age = 0; age < nights; age++) metricsToday.addDays(-age),
  ];
  return ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(() => metricsNow),
      sleepHistoryReaderProvider.overrideWithValue(
        FakeSleepHistoryReader([for (final d in dates) ...nightSpans(d)]),
      ),
      heartHistoryReaderProvider.overrideWithValue(
        FakeHeartHistoryReader(
          heartRateSamples: [
            for (final d in dates) ...overnightHeartRate(d, every),
          ],
          hrvReadings: [
            for (final d in dates)
              for (var i = 0; i < 15; i++)
                (
                  at: nightStart(d).add(Duration(minutes: 30 * i)),
                  milliseconds: 40,
                ),
          ],
        ),
      ),
    ],
  );
}

void main() {
  test('with no data both baselines are building from zero', () async {
    final container = containerFor(noDataScenario);

    final baselines = await container.read(heartBaselinesProvider.future);
    final day = await container.read(heartDayProvider.future);

    expect(baselines.hrv.today, isNull);
    expect(baselines.hrv.baseline, isA<BaselineBuilding>());
    expect(
      (baselines.restingHeartRate.baseline as BaselineBuilding).daysCollected,
      0,
    );
    expect(day.isEmpty, isTrue);
    expect(day.spo2Night, isNull);
    expect(day.stressSummary, isNull);
  });

  test('while building it keeps last night but has no deviation', () async {
    final container = containerFor(buildingScenario);

    final baselines = await container.read(heartBaselinesProvider.future);
    final building = baselines.hrv.baseline as BaselineBuilding;

    expect(baselines.hrv.today, 46);
    expect(building.daysCollected, 2);
    expect(building.daysNeeded, baselineMinDays);
    expect(baselines.hrv.deviation, isNull);
  });

  test('with full data compares last night with the baseline', () async {
    final container = containerFor(fullDataScenario);

    final baselines = await container.read(heartBaselinesProvider.future);
    final resting = baselines.restingHeartRate.deviation!;
    final hrv = baselines.hrv.deviation!;

    expect(baselines.restingHeartRate.today, 57.5);
    expect(resting.zScore, lessThan(0));
    expect(hrv.today, 46);
    expect(hrv.percent, greaterThan(0));
    expect((baselines.hrv.baseline as BaselineReady).days, 27);
  });

  test('summarises the day by hour, the night SpO2 and stress', () async {
    final container = containerFor(fullDataScenario);

    final day = await container.read(heartDayProvider.future);

    expect(day.dayStart, DateTime.utc(2026, 11, 10));
    expect(day.heartRate.hours, hasLength(24));
    expect(day.heartRate.hours[3], isNotNull);
    expect(day.heartRate.hours[12], isNull);
    expect(day.heartRate.max, 95);
    expect(day.spo2Night!.readings, 8);
    expect(day.spo2Night!.readingsBelow, 1);
    expect(day.spo2Night!.min, 89);
    expect(day.stressSummary!.readings, 18);
    expect(day.isEmpty, isFalse);
  });

  group('first sync of a new ring', () {
    test('one night at a 5 minute HR cadence has a resting HR and no '
        'baseline night yet', () async {
      final container = firstSync(nights: 1, every: const Duration(minutes: 5));

      final baselines = await container.read(heartBaselinesProvider.future);

      expect(baselines.restingHeartRate.today, closeTo(53, 1));
      expect(baselines.hrv.today, 40);
      for (final input in [baselines.restingHeartRate, baselines.hrv]) {
        expect((input.baseline as BaselineBuilding).daysCollected, 0);
      }
    });

    test('HR measured every 30 minutes, like the HRV log, never holds three '
        'readings in a 30 minute window', () async {
      final container = firstSync(
        nights: 1,
        every: const Duration(minutes: 30),
      );

      final baselines = await container.read(heartBaselinesProvider.future);

      expect(baselines.hrv.today, 40);
      expect(baselines.restingHeartRate.today, isNull);
    });

    test(
      'eight nights at a 5 minute cadence complete both baselines',
      () async {
        final container = firstSync(
          nights: 8,
          every: const Duration(minutes: 5),
        );

        final baselines = await container.read(heartBaselinesProvider.future);

        expect((baselines.restingHeartRate.baseline as BaselineReady).days, 7);
        expect((baselines.hrv.baseline as BaselineReady).days, 7);
        expect(baselines.restingHeartRate.deviation, isNotNull);
      },
    );
  });

  test('a split night still yields resting HR and HRV', () async {
    final container = containerFor(splitNightScenario);

    final baselines = await container.read(heartBaselinesProvider.future);

    expect(baselines.restingHeartRate.today, isNotNull);
    expect(baselines.hrv.deviation, isNotNull);
  });
}
