import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_source_selection.dart';
import 'package:open_ring/features/trajectory/domain/levers_view.dart';
import 'package:open_ring/features/trends/application/trends_providers.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';

final leversProvider = FutureProvider<LeversView>((ref) async {
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  try {
    final modules = await ref.watch(enabledModulesProvider.future);
    if (!modules.contains(ModuleId.trajectory)) return const LeversOff();
    if (!modules.contains(ModuleId.body)) return const LeversOff();
    return await _read(ref, today);
  } on Object catch (error) {
    debugPrint('Ring levers could not be read: $error');
    return LeversError(error);
  }
});

// Today is still partial, so steps and regularity end the day before.
Future<LeversView> _read(Ref ref, LocalDate today) async {
  final now = ref.watch(clockProvider)();
  final offset = now.timeZoneOffset;
  final end = today.addDays(-1);
  final first = end.addDays(1 - leverTrendWindowDays);
  // The day before the window pairs with its first day, and the night before
  // that one starts the evening before.
  final from = localMidnight(first.addDays(-2), offset);
  final slotsRead = ref
      .watch(activityHistoryReaderProvider)
      .activitySlots(from: first, to: end);
  final sessionsRead = readSleepSessions(
    ring: ref.watch(sleepHistoryReaderProvider),
    imported: ref.watch(importedSleepReaderProvider),
    from: from,
    to: now,
  );
  final heartRead = ref
      .watch(heartHistoryReaderProvider)
      .heartRate(from: from, to: now);
  final historyRead = ref.watch(trendHistoryProvider.future);
  // Future.wait rethrows the reader's own error, where a record wait wraps it.
  await Future.wait<Object>([slotsRead, sessionsRead, heartRead, historyRead]);
  final slots = await slotsRead;
  final sessions = await sessionsRead;
  final heartRate = await heartRead;
  final history = await historyRead;
  final spans = [for (final session in sessions) ...session.spans];
  final asleep = [
    for (final span in spans)
      if (span.isAsleep) (start: span.start, end: span.end),
  ];
  final buckets = <LocalDate, List<StepBucket>>{};
  for (final slot in slots) {
    (buckets[slot.date] ??= []).add((
      start: slot.start,
      duration: slot.duration,
      steps: slot.steps,
    ));
  }
  final steps = [
    for (final MapEntry(key: date, value: day) in buckets.entries)
      if (isValidStepDay(day, sleep: asleep))
        (
          date: date,
          value: day.fold<int>(0, (sum, b) => sum + b.steps).toDouble(),
        ),
  ];
  final worn = {
    for (final sample in heartRate)
      if (LocalDate.fromInstant(sample.at, offset) case final date
          when date.compareTo(end) <= 0)
        date,
  };
  return LeversReady({
    RingLever.steps: _reading(steps, end),
    RingLever.sleepRegularity: _reading(
      dailySleepRegularity(spans, days: worn),
      end,
    ),
    RingLever.restingHeartRate: _reading(
      history.values(TrendMetric.restingHeartRate),
      today,
    ),
    RingLever.sleepDuration: _reading(
      history.values(TrendMetric.sleepDuration),
      today,
    ),
  });
}

LeverReading _reading(List<DailyValue> values, LocalDate end) {
  final days = {
    for (final value in values)
      if (_inWindow(value.date, end) && value.value.isFinite) value.date,
  };
  return (validDays: days.length, trend: theilSen(values, end: end));
}

bool _inWindow(LocalDate date, LocalDate end) {
  final age = end.daysSince(date);
  return age >= 0 && age < leverTrendWindowDays;
}
