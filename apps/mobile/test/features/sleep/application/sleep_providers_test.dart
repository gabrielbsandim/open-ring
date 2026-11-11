import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/domain/imported_sleep_reader.dart';

import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/rem_reporting_fakes.dart';

const _watch = 'com.garmin.android.apps.connectmobile';

final class _FakeImportedSleepReader implements ImportedSleepReader {
  const new(this.value);

  final ImportedSleep value;

  @override
  Future<ImportedSleep> importedSleep({
    required DateTime from,
    required DateTime to,
  }) async => value;
}

ProviderContainer containerFor(MetricsScenario scenario) =>
    ProviderContainer.test(overrides: scenario.overrides());

void main() {
  test('with no data the week has seven unscored days', () async {
    final container = containerFor(noDataScenario);

    final week = await container.read(sleepWeekProvider.future);

    expect(week.days, hasLength(7));
    expect(week.isEmpty, isTrue);
    expect(week.latest.date, metricsToday);
    expect(week.latest.score, isA<InsufficientData<SleepFactor>>());
  });

  test('with full data last night is stitched, dated and scored', () async {
    final container = containerFor(fullDataScenario);

    final week = await container.read(sleepWeekProvider.future);
    final night = week.latest.night!;

    expect(week.days.map((d) => d.date), [
      for (var age = 6; age >= 0; age--) metricsToday.addDays(-age),
    ]);
    expect(night.asleep, const Duration(minutes: 412));
    expect(night.timeInBed, const Duration(minutes: 444));
    expect(night.timeIn(SleepPhase.light), const Duration(minutes: 226));
    expect(week.latest.scoreValue, 95);
    expect(week.latest.splitBreak, isNull);
  });

  test('keeps the nights the baselines need', () async {
    final container = containerFor(fullDataScenario);

    final nights = await container.read(sleepNightsProvider.future);

    expect(nights, hasLength(28));
    expect(nights.keys, contains(metricsToday.addDays(-27)));
  });

  test('a building baseline still scores the nights it has', () async {
    final container = containerFor(buildingScenario);

    final week = await container.read(sleepWeekProvider.future);

    expect(week.days.where((d) => d.night != null), hasLength(3));
    expect(week.days.first.score, isA<InsufficientData<SleepFactor>>());
    expect(week.latest.score, isA<Scored<SleepFactor>>());
  });

  test('a split night is joined and reports the break', () async {
    final container = containerFor(splitNightScenario);

    final week = await container.read(sleepWeekProvider.future);
    final day = week.latest;
    final split = day.splitBreak!;

    expect(day.night!.gaps, hasLength(1));
    expect(day.stretches, 2);
    expect(split.start, DateTime.utc(2026, 11, 10, 4, 12));
    expect(split.duration, const Duration(minutes: 9));
  });

  test('a ring without REM drops the REM factor', () async {
    final container = ProviderContainer.test(
      overrides: ringWithoutRemOverrides(),
    );

    final week = await container.read(sleepWeekProvider.future);
    final score = week.latest.score as Scored<SleepFactor>;

    expect(score.of(SleepFactor.rem), isNull);
    expect(
      score.contributions.fold<double>(0, (sum, c) => sum + c.weight),
      closeTo(100, 1e-9),
    );
    expect(score.of(SleepFactor.duration)!.weight, closeTo(3500 / 85, 1e-9));
    expect(week.remMeasured, isFalse);
  });

  test('until the ring is judged, REM stays in the score', () async {
    for (final reporting in [RemReporting.unknown, RemReporting.reported]) {
      final container = ProviderContainer.test(
        overrides: ringWithoutRemOverrides(reporting: reporting),
      );

      final week = await container.read(sleepWeekProvider.future);
      final score = week.latest.score as Scored<SleepFactor>;

      expect(week.remMeasured, isTrue, reason: '$reporting');
      expect(score.of(SleepFactor.rem)?.weight, 15, reason: '$reporting');
    }
  });

  test('with no reader the flag defaults to measured', () async {
    final container = containerFor(fullDataScenario);

    expect(
      await container.read(remReportingProvider.future),
      RemReporting.unknown,
    );
    expect(await container.read(remMeasuredProvider.future), isTrue);
  });

  test('a night the ring missed comes from the next source', () async {
    final missed = metricsToday.addDays(-1);
    final container = ProviderContainer.test(
      overrides: [
        ...noDataScenario.overrides(),
        importedSleepReaderProvider.overrideWithValue(
          _FakeImportedSleepReader((
            priority: const [ringSource, _watch],
            spans: {_watch: nightSpans(missed)},
          )),
        ),
      ],
    );

    final nights = await container.read(sleepNightsProvider.future);

    expect(nights.keys, [missed]);
    expect(nights[missed]!.asleep, const Duration(minutes: 412));
  });
}
