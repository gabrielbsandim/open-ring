import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/trends/application/trends_providers.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';

import '../../../helpers/metrics_fakes.dart';

void main() {
  test('reads every series from the existing readers', () async {
    final container = ProviderContainer.test(
      overrides: fullDataScenario.overrides(),
    );

    final history = await container.read(trendHistoryProvider.future);
    final resting = history.series(
      TrendMetric.restingHeartRate,
      TrendRange.month,
    );
    final steps = history.series(TrendMetric.steps, TrendRange.month);

    expect(resting.measuredDays, 28);
    expect(resting.latest, 57.5);
    expect(
      history.series(TrendMetric.sleepScore, TrendRange.week).hasStats,
      isTrue,
    );
    expect(history.series(TrendMetric.spo2, TrendRange.week).latest, isNotNull);
    expect(steps.latest, 2224);
    expect(steps.measuredDays, 28);
    expect(history.bands.keys, contains(TrendMetric.restingHeartRate));
    expect(history.bands.keys, contains(TrendMetric.hrv));
  });

  test('without data the history is empty', () async {
    final container = ProviderContainer.test(
      overrides: noDataScenario.overrides(),
    );

    final history = await container.read(trendHistoryProvider.future);

    expect(history.isEmpty, isTrue);
  });

  test('reloads when the data revision moves', () async {
    final days = <DailyActivity>[];
    final container = ProviderContainer.test(
      overrides: [
        clockProvider.overrideWithValue(() => metricsNow),
        sleepHistoryReaderProvider.overrideWithValue(
          FakeSleepHistoryReader(const []),
        ),
        heartHistoryReaderProvider.overrideWithValue(FakeHeartHistoryReader()),
        activityHistoryReaderProvider.overrideWithValue(
          FakeActivityHistoryReader(days),
        ),
      ],
    );
    final before = await container.read(trendHistoryProvider.future);

    days.add(
      DailyActivity(
        date: metricsToday.addDays(-1),
        steps: 6400,
        activeKilocalories: 250,
        distanceMeters: 4100,
      ),
    );
    container.read(dataRevisionProvider.notifier).bump();
    final after = await container.read(trendHistoryProvider.future);

    expect(before.isEmpty, isTrue);
    expect(after.series(TrendMetric.steps, TrendRange.week).mean, 6400);
  });
}
