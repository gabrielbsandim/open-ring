import 'package:flutter_riverpod/misc.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/heart/domain/heart_history_reader.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/domain/sleep_history_reader.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';

import 'ble_fakes.dart';
import 'ring_fakes.dart';

final metricsNow = DateTime.utc(2026, 11, 10, 9);
const metricsToday = LocalDate(2026, 11, 10);

const List<(SleepPhase, int)> _nightPattern = [
  (SleepPhase.awake, 14),
  (SleepPhase.light, 26),
  (SleepPhase.deep, 45),
  (SleepPhase.light, 25),
  (SleepPhase.rem, 20),
  (SleepPhase.light, 40),
  (SleepPhase.deep, 33),
  (SleepPhase.light, 37),
  (SleepPhase.rem, 30),
  (SleepPhase.light, 24),
  (SleepPhase.awake, 9),
  (SleepPhase.light, 42),
  (SleepPhase.rem, 30),
  (SleepPhase.light, 32),
  (SleepPhase.awake, 9),
  (SleepPhase.rem, 28),
];

const _splitIndex = 10;

DateTime nightStart(LocalDate date) =>
    DateTime.utc(date.year, date.month, date.day - 1, 23, 18);

List<SleepSpan> nightSpans(LocalDate date, {bool split = false}) {
  var at = nightStart(date);
  final spans = <SleepSpan>[];
  for (var i = 0; i < _nightPattern.length; i++) {
    final (phase, minutes) = _nightPattern[i];
    final end = at.add(Duration(minutes: minutes));
    if (!(split && i == _splitIndex)) {
      spans.add(
        SleepSpan(start: at, end: end, phase: phase, utcOffset: Duration.zero),
      );
    }
    at = end;
  }
  return spans;
}

class FakeSleepHistoryReader implements SleepHistoryReader {
  new(this.spans);

  final List<SleepSpan> spans;

  @override
  Future<List<SleepSpan>> sleepSpans({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final s in spans)
      if (s.end.isAfter(from) && s.start.isBefore(to)) s,
  ];
}

bool _inRange(DateTime at, DateTime from, DateTime to) =>
    !at.isBefore(from) && at.isBefore(to);

class FakeHeartHistoryReader implements HeartHistoryReader {
  new({
    this.heartRateSamples = const [],
    this.hrvReadings = const [],
    this.spo2Readings = const [],
    this.stressReadings = const [],
  });

  final List<BpmSample> heartRateSamples;
  final List<HrvReading> hrvReadings;
  final List<Spo2Reading> spo2Readings;
  final List<StressReading> stressReadings;

  @override
  Future<List<BpmSample>> heartRate({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final s in heartRateSamples)
      if (_inRange(s.at, from, to)) s,
  ];

  @override
  Future<List<HrvReading>> hrv({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final r in hrvReadings)
      if (_inRange(r.at, from, to)) r,
  ];

  @override
  Future<List<Spo2Reading>> spo2({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final r in spo2Readings)
      if (_inRange(r.at, from, to)) r,
  ];

  @override
  Future<List<StressReading>> stress({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final r in stressReadings)
      if (_inRange(r.at, from, to)) r,
  ];
}

class FakeActivityHistoryReader implements ActivityHistoryReader {
  new(this.days, {this.slots = const []});

  final List<DailyActivity> days;
  final List<ActivitySlot> slots;

  @override
  Future<List<ActivitySlot>> activitySlots({
    required LocalDate from,
    required LocalDate to,
  }) async => [
    for (final s in slots)
      if (s.date.compareTo(from) >= 0 && s.date.compareTo(to) <= 0) s,
  ];

  @override
  Future<List<DailyActivity>> dailyActivity({
    required LocalDate from,
    required LocalDate to,
  }) async => [
    for (final d in days)
      if (d.date.compareTo(from) >= 0 && d.date.compareTo(to) <= 0) d,
  ];
}

class FakeRingStatusReader implements RingStatusReader {
  new(this.value);

  final RingStatus value;

  @override
  Future<RingStatus> status() async => value;
}

final class MetricsScenario {
  const new({
    required this.nights,
    required this.activityDays,
    required this.ring,
    this.splitToday = false,
    this.now,
  });

  final int nights;
  final int activityDays;
  final RingStatus ring;
  final bool splitToday;
  final DateTime? now;

  List<SleepSpan> get spans => [
    for (var age = 0; age < nights; age++)
      ...nightSpans(metricsToday.addDays(-age), split: splitToday && age == 0),
  ];

  FakeHeartHistoryReader get heart {
    if (nights == 0) return FakeHeartHistoryReader();
    final heartRate = <BpmSample>[];
    final hrv = <HrvReading>[];
    for (var age = 0; age < nights; age++) {
      final start = nightStart(metricsToday.addDays(-age));
      final base = age == 0 ? 56 : 58 + age % 3;
      for (var i = 0; i < 88; i++) {
        heartRate.add((
          at: start.add(Duration(minutes: 5 * i)),
          bpm: base + i % 6,
        ));
      }
      for (var i = 0; i < 14; i++) {
        hrv.add((
          at: start.add(Duration(minutes: 30 * i + 10)),
          milliseconds: age == 0 ? 46 : 40 + age % 5,
        ));
      }
    }
    final morning = DateTime.utc(2026, 11, 10, 6, 45);
    for (var i = 0; i < 27; i++) {
      heartRate.add((
        at: morning.add(Duration(minutes: 5 * i)),
        bpm: 80 + i % 16,
      ));
    }
    const spo2Values = [97, 96, 95, 89, 97, 98, 97, 96];
    final spo2Start = DateTime.utc(2026, 11, 9, 23, 30);
    const stressLevels = [20, 24, 30, 45, 52, 60, 78];
    final dayStart = DateTime.utc(2026, 11, 10);
    return FakeHeartHistoryReader(
      heartRateSamples: heartRate,
      hrvReadings: hrv,
      spo2Readings: [
        for (var i = 0; i < spo2Values.length; i++)
          (at: spo2Start.add(Duration(hours: i)), percent: spo2Values[i]),
      ],
      stressReadings: [
        for (var i = 0; i < 18; i++)
          (
            at: dayStart.add(Duration(minutes: 30 * i)),
            level: stressLevels[i % stressLevels.length],
          ),
      ],
    );
  }

  List<DailyActivity> get activity => [
    for (var age = 0; age < activityDays; age++)
      DailyActivity(
        date: metricsToday.addDays(-age),
        steps: age == 0 ? 2224 : 7000 + age * 50,
        activeKilocalories: age == 0 ? 87 : 380.0 + (age % 4) * 20,
        distanceMeters: age == 0 ? 1540 : 5000,
      ),
  ];

  List<ActivitySlot> get slots => [
    if (activityDays > 0)
      for (var hour = 0; hour < hourlyStepPattern.length; hour++)
        ActivitySlot(
          start: DateTime.utc(2026, 11, 10, hour),
          utcOffset: Duration.zero,
          duration: const Duration(hours: 1),
          steps: hourlyStepPattern[hour],
          activeKilocalories: hourlyStepPattern[hour] / 25,
          distanceMeters: hourlyStepPattern[hour] * 0.7,
        ),
  ];

  PairedRing? get pairedRing => ring.paired
      ? PairedRing(deviceId: fakeRingId, lastSyncAt: ring.lastSyncAt)
      : null;

  List<Override> overrides() => [
    clockProvider.overrideWithValue(() => now ?? metricsNow),
    sleepHistoryReaderProvider.overrideWithValue(FakeSleepHistoryReader(spans)),
    heartHistoryReaderProvider.overrideWithValue(heart),
    activityHistoryReaderProvider.overrideWithValue(
      FakeActivityHistoryReader(activity, slots: slots),
    ),
    ringStatusReaderProvider.overrideWithValue(FakeRingStatusReader(ring)),
  ];
}

const hourlyStepPattern = [
  0,
  0,
  0,
  0,
  0,
  0,
  40,
  180,
  95,
  60,
  30,
  140,
  210,
  90,
  70,
  45,
  120,
  160,
  620,
  240,
  110,
  14,
  0,
  0,
];

final freshRing = RingStatus(
  paired: true,
  name: 'R09_C0FE',
  model: 'R09',
  firmware: '3.00.03',
  batteryCharging: true,
  lastSyncAt: metricsNow.subtract(const Duration(minutes: 20)),
  batteryPercent: 68,
);

const noDataScenario = MetricsScenario(
  nights: 0,
  activityDays: 0,
  ring: RingStatus.unpaired,
);

final fullDataScenario = MetricsScenario(
  nights: 28,
  activityDays: 29,
  ring: freshRing,
);

final buildingScenario = MetricsScenario(
  nights: 3,
  activityDays: 3,
  ring: freshRing,
);

final splitNightScenario = MetricsScenario(
  nights: 28,
  activityDays: 29,
  ring: freshRing,
  splitToday: true,
);

final offlineScenario = MetricsScenario(
  nights: 28,
  activityDays: 29,
  ring: RingStatus(
    paired: true,
    name: 'R09_C0FE',
    model: 'R09',
    lastSyncAt: metricsNow.subtract(const Duration(hours: 9)),
    batteryPercent: 14,
  ),
);

List<Override> metricsOverrides(
  MetricsScenario scenario, {
  List<Override> ring = const [],
}) => [
  ...bleOverrides(),
  ...(ring.isEmpty
      ? ringOverrides(paired: scenario.pairedRing, clock: () => metricsNow)
      : ring),
  ...scenario.overrides(),
];
