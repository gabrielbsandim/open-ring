import 'package:ring_driver/ring_driver.dart';

import 'fake_ring_driver.dart';

final syncNow = DateTime(2026, 11, 10, 8);

final nightStart = DateTime(2026, 11, 9, 23);

final List<ActivityBucket> eveningActivity = [
  ActivityBucket(
    start: DateTime(2026, 11, 9, 22),
    duration: const Duration(minutes: 15),
    steps: 420,
    distanceMeters: 310,
    activeKilocalories: 18.5,
  ),
  ActivityBucket(
    start: DateTime(2026, 11, 9, 22, 15),
    duration: const Duration(minutes: 15),
    steps: 120,
    distanceMeters: 90,
    activeKilocalories: 5.25,
  ),
];

final List<HeartRateSample> nightHeartRate = [
  HeartRateSample(at: DateTime(2026, 11, 9, 22), bpm: 64),
  HeartRateSample(at: DateTime(2026, 11, 9, 22, 5), bpm: 61),
  HeartRateSample(at: DateTime(2026, 11, 10, 7, 55), bpm: 58),
];

final List<SleepSegment> lastNight = [
  SleepSegment(
    start: nightStart,
    end: DateTime(2026, 11, 10, 1),
    stage: SleepStage.light,
  ),
  SleepSegment(
    start: DateTime(2026, 11, 10, 1),
    end: DateTime(2026, 11, 10, 2, 30),
    stage: SleepStage.deep,
  ),
  SleepSegment(
    start: DateTime(2026, 11, 10, 2, 30),
    end: DateTime(2026, 11, 10, 3),
    stage: SleepStage.rem,
  ),
  SleepSegment(
    start: DateTime(2026, 11, 10, 3),
    end: DateTime(2026, 11, 10, 7),
    stage: SleepStage.light,
  ),
];

FakeRingDriver loadedDriver() => FakeRingDriver()
  ..activity = [...eveningActivity]
  ..heartRate = [...nightHeartRate]
  ..spo2 = [Spo2Sample(at: DateTime(2026, 11, 10, 3), percent: 97)]
  ..stress = [StressSample(at: DateTime(2026, 11, 9, 21, 30), level: 40)]
  ..hrv = [HrvSample(at: DateTime(2026, 11, 10, 2), milliseconds: 55)]
  ..sleep = [...lastNight];
