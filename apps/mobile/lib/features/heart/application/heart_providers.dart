import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/heart/application/heart_view.dart';
import 'package:open_ring/features/heart/domain/heart_history_reader.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';

final heartHistoryReaderProvider = Provider<HeartHistoryReader>(
  (ref) => const EmptyHeartHistoryReader(),
);

typedef _Nightly = ({double? restingHeartRate, double? hrv});

final heartBaselinesProvider = FutureProvider<HeartBaselines>((ref) async {
  ref.watch(dataRevisionProvider);
  final reader = ref.watch(heartHistoryReaderProvider);
  final today = ref.watch(currentDateProvider);
  final nights = await ref.watch(sleepNightsProvider.future);
  final nightly = await _nightlyHeart(reader, nights);
  final restingHistory = [
    for (final MapEntry(key: date, value: n) in nightly.entries)
      if (n.restingHeartRate case final value?) (date: date, value: value),
  ];
  final hrvHistory = [
    for (final MapEntry(key: date, value: n) in nightly.entries)
      if (n.hrv case final value?) (date: date, value: value),
  ];
  return HeartBaselines(
    restingHeartRate: BaselineInput(
      today: nightly[today]?.restingHeartRate,
      baseline: restingHeartRateBaseline(restingHistory, today: today),
    ),
    hrv: BaselineInput(
      today: nightly[today]?.hrv,
      baseline: hrvBaseline(hrvHistory, today: today),
    ),
  );
});

Future<Map<LocalDate, _Nightly>> _nightlyHeart(
  HeartHistoryReader reader,
  Map<LocalDate, SleepNight> nights,
) async {
  if (nights.isEmpty) return const {};
  final from = nights.values.map((n) => n.start).reduce(_earlier);
  final to = nights.values.map((n) => n.end).reduce(_later);
  final (heartRate, hrv) = await (
    reader.heartRate(from: from, to: to),
    reader.hrv(from: from, to: to),
  ).wait;
  return {
    for (final MapEntry(key: date, value: night) in nights.entries)
      date: (
        restingHeartRate: restingHeartRate(
          heartRate.where((s) => _within(s.at, night.start, night.end)),
        ),
        hrv: nightlyHrv(
          hrv.where((r) => _within(r.at, night.start, night.end)),
        ),
      ),
  };
}

final heartDayProvider = FutureProvider<HeartDayView>((ref) async {
  ref.watch(dataRevisionProvider);
  final reader = ref.watch(heartHistoryReaderProvider);
  final today = ref.watch(currentDateProvider);
  final now = ref.watch(clockProvider)();
  final offset = now.timeZoneOffset;
  final dayStart = localMidnight(today, offset);
  final (nights, baselines) = await (
    ref.watch(sleepNightsProvider.future),
    ref.watch(heartBaselinesProvider.future),
  ).wait;
  final lastNight = nights[today];
  final spo2From = lastNight == null
      ? dayStart
      : _earlier(lastNight.start, dayStart);
  final (heartRate, hrv, spo2, stress) = await (
    reader.heartRate(from: dayStart, to: now),
    reader.hrv(from: dayStart, to: now),
    reader.spo2(from: spo2From, to: now),
    reader.stress(from: dayStart, to: now),
  ).wait;
  final dayStress = [
    for (final r in stress)
      if (_within(r.at, dayStart, now)) r,
  ];
  return HeartDayView(
    dayStart: dayStart,
    until: now,
    utcOffset: offset,
    heartRate: HourlySeries.of(dayStart, [
      for (final s in heartRate)
        if (s.bpm > 0) (at: s.at, value: s.bpm.toDouble()),
    ]),
    hrv: HourlySeries.of(dayStart, [
      for (final r in hrv)
        if (r.milliseconds > 0) (at: r.at, value: r.milliseconds.toDouble()),
    ]),
    spo2: HourlySeries.of(dayStart, [
      for (final r in spo2)
        if (r.percent >= spo2MinPlausible && r.percent <= 100)
          (at: r.at, value: r.percent.toDouble()),
    ]),
    stress: HourlySeries.of(dayStart, [
      for (final r in dayStress)
        if (r.level >= 1 && r.level <= 100)
          (at: r.at, value: r.level.toDouble()),
    ]),
    baselines: baselines,
    spo2Night: lastNight == null
        ? null
        : spo2NightSummary(spo2, from: lastNight.start, to: lastNight.end),
    stressSummary: stressDaySummary(dayStress),
  );
});

bool _within(DateTime at, DateTime from, DateTime to) =>
    !at.isBefore(from) && at.isBefore(to);

DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
