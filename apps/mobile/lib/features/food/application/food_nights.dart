import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/domain/overall_history.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_source_selection.dart';

/// Comparisons update on Mondays over the 90 nights ending on the closed
/// Sunday before the current week.
LocalDate foodCompareLastNight(LocalDate today) => mondayOf(today).addDays(-1);

LocalDate foodFirstNight(LocalDate today) =>
    mondayOf(today).addDays(-foodCompareNights);

/// The first asleep span at its capture wall clock, as a UTC flagged DateTime
/// whose fields are local time, matching a meal's entry wall clock.
DateTime? sleepOnsetWallClock(SleepNight night) {
  for (final span in night.spans) {
    if (span.phase != SleepPhase.awake) {
      return span.start.toUtc().add(span.utcOffset);
    }
  }
  return null;
}

/// Maps [night] (keyed by wake date) to the food day it closes (`wake - 1`).
FoodNight foodNightOf(
  SleepNight night, {
  Iterable<BpmSample> heartRate = const [],
  Iterable<HrvReading> hrv = const [],
}) => FoodNight(
  day: night.date.addDays(-1),
  sleepOnset: sleepOnsetWallClock(night),
  heartRate: restingHeartRate(
    heartRate.where(
      (s) => !s.at.isBefore(night.start) && s.at.isBefore(night.end),
    ),
  ),
  hrv: nightlyHrv(
    hrv.where((r) => !r.at.isBefore(night.start) && r.at.isBefore(night.end)),
  ),
);

List<FoodNight> collectFoodNights({
  required LocalDate today,
  required Iterable<SleepNight> nights,
  Iterable<BpmSample> heartRate = const [],
  Iterable<HrvReading> hrv = const [],
  Set<LocalDate> excluded = const {},
}) {
  final kept = _keptSleepNights(
    today: today,
    nights: nights,
    excluded: excluded,
  );
  return [
    for (final night in kept)
      foodNightOf(night, heartRate: heartRate, hrv: hrv),
  ];
}

Map<LocalDate, DateTime> sleepOnsetsOf(Iterable<FoodNight> nights) => {
  for (final night in nights) night.day: ?night.sleepOnset,
};

final foodNightsProvider = FutureProvider<List<FoodNight>>((ref) async {
  if (!ref.watch(foodEnabledProvider)) return const [];
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentFoodDayProvider);
  final now = ref.watch(clockProvider)();
  final openScoreOn = ref.watch(
    enabledModulesProvider.select(
      (modules) => modules.value?.contains(ModuleId.openScore) ?? false,
    ),
  );
  final excluded = openScoreOn
      ? overallExcluded(await ref.watch(dayTagsProvider.future))
      : const <LocalDate>{};
  final first = foodFirstNight(today);
  // Two extra days cover a night that started before midnight in a positive
  // UTC offset.
  final from = DateTime.utc(
    first.year,
    first.month,
    first.day,
  ).subtract(const Duration(days: 2));
  final byDate = await readSleepNights(
    ring: ref.watch(sleepHistoryReaderProvider),
    imported: ref.watch(importedSleepReaderProvider),
    from: from,
    to: now,
  );
  final kept = _keptSleepNights(
    today: today,
    nights: byDate.values,
    excluded: excluded,
  );
  if (kept.isEmpty) return const [];
  final heartReader = ref.watch(heartHistoryReaderProvider);
  final minStart = kept
      .map((n) => n.start)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final maxEnd = kept.map((n) => n.end).reduce((a, b) => a.isAfter(b) ? a : b);
  final (heartRate, hrv) = await (
    heartReader.heartRate(from: minStart, to: maxEnd),
    heartReader.hrv(from: minStart, to: maxEnd),
  ).wait;
  return [
    for (final night in kept)
      foodNightOf(night, heartRate: heartRate, hrv: hrv),
  ];
});

List<SleepNight> _keptSleepNights({
  required LocalDate today,
  required Iterable<SleepNight> nights,
  Set<LocalDate> excluded = const {},
}) {
  final first = foodFirstNight(today);
  final last = today.addDays(-1);
  return [
    for (final night in nights)
      if (_inWindow(night.date.addDays(-1), first: first, last: last) &&
          !excluded.contains(night.date.addDays(-1)))
        night,
  ]..sort((a, b) => a.date.compareTo(b.date));
}

bool _inWindow(
  LocalDate day, {
  required LocalDate first,
  required LocalDate last,
}) => day.compareTo(first) >= 0 && day.compareTo(last) <= 0;
