import 'package:meta/meta.dart';

enum RingCapability {
  battery,
  activity,
  heartRateLog,
  spo2,
  stress,
  hrv,
  sleep,
  liveHeartRate,
  liveSpo2,
}

enum RingLinkState { disconnected, connecting, connected, disconnecting }

@immutable
final class RingIdentity {
  const new({
    required this.deviceId,
    required this.name,
    this.model,
    this.firmware,
  });

  final String deviceId;
  final String name;
  final String? model;
  final String? firmware;
}

@immutable
final class BatteryStatus {
  const new({required this.percent, required this.charging});

  final int percent;
  final bool charging;
}

@immutable
final class ActivityBucket {
  const new({
    required this.start,
    required this.duration,
    required this.steps,
    required this.distanceMeters,
    required this.activeKilocalories,
  });

  final DateTime start;
  final Duration duration;
  final int steps;
  final int distanceMeters;
  final double activeKilocalories;
}

@immutable
final class HeartRateSample {
  const new({required this.at, required this.bpm});

  final DateTime at;
  final int bpm;
}

@immutable
final class Spo2Sample {
  const new({required this.at, required this.percent});

  final DateTime at;
  final int percent;
}

@immutable
final class StressSample {
  const new({required this.at, required this.level});

  final DateTime at;
  final int level;
}

@immutable
final class HrvSample {
  const new({required this.at, required this.milliseconds});

  final DateTime at;
  final int milliseconds;
}

enum SleepStage { light, deep, rem, awake }

@immutable
final class SleepSegment {
  const new({required this.start, required this.end, required this.stage});

  final DateTime start;
  final DateTime end;
  final SleepStage stage;
}

enum LiveKind { heartRate, spo2 }

@immutable
final class LiveReading {
  const new({required this.kind, required this.value, required this.at});

  final LiveKind kind;
  final int value;
  final DateTime at;
}
