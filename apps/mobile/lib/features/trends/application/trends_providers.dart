import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/heart/domain/heart_history_reader.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_source_selection.dart';
import 'package:open_ring/features/trends/domain/trend_history.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';

typedef _NightSamples = ({
  List<BpmSample> heartRate,
  List<HrvReading> hrv,
  List<Spo2Reading> spo2,
});

final trendHistoryProvider = FutureProvider<TrendHistory>((ref) async {
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  final now = ref.watch(clockProvider)();
  final sleepReader = ref.watch(sleepHistoryReaderProvider);
  final importedReader = ref.watch(importedSleepReaderProvider);
  final heartReader = ref.watch(heartHistoryReaderProvider);
  final activityReader = ref.watch(activityHistoryReaderProvider);
  final goal = ref.watch(sleepGoalProvider);
  final remMeasured = await ref.watch(remMeasuredProvider.future);
  // Two extra days so the oldest night, which starts the evening before its date, is complete.
  final (byDate, activity) = await (
    readSleepNights(
      ring: sleepReader,
      imported: importedReader,
      from: now.subtract(Duration(days: trendHistoryDays + 2)),
      to: now,
    ),
    activityReader.dailyActivity(
      from: today.addDays(1 - trendHistoryDays),
      to: today,
    ),
  ).wait;
  final nights = byDate.values.toList();
  final samples = await _nightSamples(heartReader, nights);
  return TrendHistory.collect(
    today: today,
    nights: nights,
    heartRate: samples.heartRate,
    hrv: samples.hrv,
    spo2: samples.spo2,
    activity: activity,
    sleepGoal: goal,
    remMeasured: remMeasured,
  );
});

Future<_NightSamples> _nightSamples(
  HeartHistoryReader reader,
  List<SleepNight> nights,
) async {
  if (nights.isEmpty) {
    return (
      heartRate: const <BpmSample>[],
      hrv: const <HrvReading>[],
      spo2: const <Spo2Reading>[],
    );
  }
  final from = nights
      .map((n) => n.start)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final to = nights.map((n) => n.end).reduce((a, b) => a.isAfter(b) ? a : b);
  final (heartRate, hrv, spo2) = await (
    reader.heartRate(from: from, to: to),
    reader.hrv(from: from, to: to),
    reader.spo2(from: from, to: to),
  ).wait;
  return (heartRate: heartRate, hrv: hrv, spo2: spo2);
}
