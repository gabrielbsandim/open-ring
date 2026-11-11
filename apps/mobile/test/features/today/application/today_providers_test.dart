import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/today/application/readiness_trend.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';

import '../../../helpers/metrics_fakes.dart';

ProviderContainer containerFor(MetricsScenario scenario) =>
    ProviderContainer.test(overrides: scenario.overrides());

void main() {
  test('with no data readiness lists every required input', () async {
    final container = containerFor(noDataScenario);

    final readiness = await container.read(readinessProvider.future);
    final today = await container.read(todayViewProvider.future);

    expect(readiness.score, isA<InsufficientData<ReadinessFactor>>());
    expect((readiness.score as InsufficientData<ReadinessFactor>).missing, [
      ReadinessFactor.sleep,
      ReadinessFactor.hrv,
      ReadinessFactor.restingHeartRate,
    ]);
    expect(readiness.activityLoad, isNull);
    expect(today.freshness, SyncFreshness.unpaired);
    expect(today.activity, isNull);
  });

  test('while the baseline builds only the heart inputs are missing', () async {
    final container = containerFor(buildingScenario);

    final readiness = await container.read(readinessProvider.future);
    final missing =
        (readiness.score as InsufficientData<ReadinessFactor>).missing;

    expect(missing, [ReadinessFactor.hrv, ReadinessFactor.restingHeartRate]);
    expect(readiness.building!.daysCollected, 2);
    expect(readiness.baselineNights, isNull);
    expect(readiness.value, isNull);
  });

  test('with full data readiness is scored from all four inputs', () async {
    final container = containerFor(fullDataScenario);

    final readiness = await container.read(readinessProvider.future);
    final scored = readiness.score as Scored<ReadinessFactor>;

    expect(scored.contributions.map((c) => c.factor), ReadinessFactor.values);
    expect(readiness.value, inInclusiveRange(0, 100));
    expect(readiness.contribution(ReadinessFactor.sleep)!.value, 95);
    expect(readiness.activityLoad, isNotNull);
    expect(readiness.baselineNights, 27);
  });

  test('without activity history the load weight is shared', () async {
    final container = ProviderContainer.test(
      overrides: const MetricsScenario(
        nights: 28,
        activityDays: 3,
        ring: RingStatus.unpaired,
      ).overrides(),
    );

    final readiness = await container.read(readinessProvider.future);
    final scored = readiness.score as Scored<ReadinessFactor>;

    expect(scored.of(ReadinessFactor.activityLoad), isNull);
    expect(
      scored.contributions.fold<double>(0, (sum, c) => sum + c.weight),
      closeTo(100, 1e-9),
    );
  });

  test('a recent sync is fresh and carries today activity', () async {
    final container = containerFor(fullDataScenario);

    final today = await container.read(todayViewProvider.future);

    expect(today.freshness, SyncFreshness.fresh);
    expect(today.activity!.steps, 2224);
    expect(today.lastNight.scoreValue, 95);
  });

  test('a sync older than three hours is stale', () async {
    final container = containerFor(offlineScenario);

    final today = await container.read(todayViewProvider.future);

    expect(today.freshness, SyncFreshness.stale);
    expect(today.ring.batteryPercent, 14);
  });

  group('readiness trend', () {
    test('has one slot per day and today matches the score', () async {
      final container = containerFor(fullDataScenario);

      final trend = await container.read(readinessTrendProvider.future);
      final readiness = await container.read(readinessProvider.future);

      expect(trend.values, hasLength(readinessTrendDays));
      expect(trend.scored, hasLength(readinessTrendDays));
      expect(trend.values.last, readiness.value);
      expect(trend.firstDate, metricsToday.addDays(-13));
      expect(trend.lowest, lessThanOrEqualTo(trend.average!));
      expect(trend.highest, greaterThanOrEqualTo(trend.average!));
    });

    test('a day without enough earlier nights stays a gap', () async {
      final container = containerFor(
        MetricsScenario(nights: 10, activityDays: 0, ring: freshRing),
      );

      final trend = await container.read(readinessTrendProvider.future);

      expect(trend.values.sublist(0, 11), everyElement(isNull));
      expect(trend.values.sublist(11), everyElement(isNotNull));
    });

    test('with no data it is empty and has no average', () async {
      final container = containerFor(noDataScenario);

      final trend = await container.read(readinessTrendProvider.future);

      expect(trend.isEmpty, isTrue);
      expect(trend.average, isNull);
      expect(trend.lowest, isNull);
      expect(trend.highest, isNull);
    });
  });
}
