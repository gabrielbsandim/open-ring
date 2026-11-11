import 'package:flutter_riverpod/misc.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/domain/rem_reporting_reader.dart';
import 'package:open_ring/features/today/application/today_providers.dart';

import 'ble_fakes.dart';
import 'metrics_fakes.dart';
import 'ring_fakes.dart';

final class FixedRemReportingReader implements RemReportingReader {
  const new(this.value);

  final RemReporting value;

  @override
  Future<RemReporting> pairedRing() async => value;
}

List<SleepSpan> withoutRem(List<SleepSpan> spans) => [
  for (final span in spans)
    SleepSpan(
      start: span.start,
      end: span.end,
      phase: span.phase == SleepPhase.rem ? SleepPhase.light : span.phase,
      utcOffset: span.utcOffset,
    ),
];

List<Override> ringWithoutRemOverrides({
  RemReporting reporting = RemReporting.absent,
}) => [
  ...bleOverrides(),
  ...ringOverrides(
    paired: fullDataScenario.pairedRing,
    clock: () => metricsNow,
  ),
  clockProvider.overrideWithValue(() => metricsNow),
  sleepHistoryReaderProvider.overrideWithValue(
    FakeSleepHistoryReader(withoutRem(fullDataScenario.spans)),
  ),
  remReportingReaderProvider.overrideWithValue(
    FixedRemReportingReader(reporting),
  ),
];

List<Override> todayWithoutRemOverrides({
  RemReporting reporting = RemReporting.absent,
}) => [
  ...ringWithoutRemOverrides(reporting: reporting),
  heartHistoryReaderProvider.overrideWithValue(fullDataScenario.heart),
  activityHistoryReaderProvider.overrideWithValue(
    FakeActivityHistoryReader(
      fullDataScenario.activity,
      slots: fullDataScenario.slots,
    ),
  ),
  ringStatusReaderProvider.overrideWithValue(
    FakeRingStatusReader(fullDataScenario.ring),
  ),
];
