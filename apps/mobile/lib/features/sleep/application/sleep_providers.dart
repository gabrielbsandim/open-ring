import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/sleep/application/sleep_source_selection.dart';
import 'package:open_ring/features/sleep/application/sleep_view.dart';
import 'package:open_ring/features/sleep/domain/imported_sleep_reader.dart';
import 'package:open_ring/features/sleep/domain/rem_reporting_reader.dart';
import 'package:open_ring/features/sleep/domain/sleep_history_reader.dart';

const int sleepHistoryDays = baselineWindowDays;
const sleepWeekDays = 7;

final sleepHistoryReaderProvider = Provider<SleepHistoryReader>(
  (ref) => const EmptySleepHistoryReader(),
);

final importedSleepReaderProvider = Provider<ImportedSleepReader>(
  (ref) => const NoImportedSleepReader(),
);

final sleepGoalProvider = Provider<Duration>((ref) => defaultSleepGoal);

final remReportingReaderProvider = Provider<RemReportingReader>(
  (ref) => const UnknownRemReportingReader(),
);

final remReportingProvider = FutureProvider<RemReporting>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(remReportingReaderProvider).pairedRing();
});

final remMeasuredProvider = FutureProvider<bool>(
  (ref) async => (await ref.watch(remReportingProvider.future)).measured,
);

final sleepNightsProvider = FutureProvider<Map<LocalDate, SleepNight>>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  final now = ref.watch(clockProvider)();
  // Two extra days so the oldest night, which starts the evening before its date, is complete.
  final byDate = await readSleepNights(
    ring: ref.watch(sleepHistoryReaderProvider),
    imported: ref.watch(importedSleepReaderProvider),
    from: now.subtract(const Duration(days: sleepHistoryDays + 2)),
    to: now,
  );
  return {
    for (final MapEntry(key: date, value: night) in byDate.entries)
      if (_kept(today.daysSince(date))) date: night,
  };
});

bool _kept(int age) => age >= 0 && age <= sleepHistoryDays;

final sleepWeekProvider = FutureProvider<SleepWeekView>((ref) async {
  final today = ref.watch(currentDateProvider);
  final goal = ref.watch(sleepGoalProvider);
  final remMeasured = await ref.watch(remMeasuredProvider.future);
  final nights = await ref.watch(sleepNightsProvider.future);
  return SleepWeekView(
    goal: goal,
    remMeasured: remMeasured,
    days: [
      for (var age = sleepWeekDays - 1; age >= 0; age--)
        SleepDayView.of(
          today.addDays(-age),
          nights[today.addDays(-age)],
          goal: goal,
          remMeasured: remMeasured,
        ),
    ],
  );
});
