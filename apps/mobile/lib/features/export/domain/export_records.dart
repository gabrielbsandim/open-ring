import 'package:meta/meta.dart';
import 'package:open_ring/features/export/domain/offset_time.dart';
import 'package:ring_driver/ring_driver.dart';

const exportSchemaVersion = 1;

@immutable
sealed class ExportRecord {
  const new();

  List<Object?> get values;
}

final class SampleRecord extends ExportRecord {
  const new({required this.at, required this.deviceId, required this.value});

  final OffsetTime at;
  final String deviceId;
  final int value;

  @override
  List<Object?> get values => [at, deviceId, value];
}

final class SleepStageRecord extends ExportRecord {
  const new({
    required this.sessionStart,
    required this.start,
    required this.end,
    required this.deviceId,
    required this.stage,
  });

  final OffsetTime sessionStart;
  final OffsetTime start;
  final OffsetTime end;
  final String deviceId;
  final SleepStage stage;

  @override
  List<Object?> get values => [
    sessionStart,
    start,
    end,
    deviceId,
    stage.name,
    (end.utcMs - start.utcMs) ~/ Duration.millisecondsPerSecond,
  ];
}

final class ActivityRecord extends ExportRecord {
  const new({
    required this.start,
    required this.duration,
    required this.deviceId,
    required this.steps,
    required this.distanceMeters,
    required this.activeKilocalories,
  });

  final OffsetTime start;
  final Duration duration;
  final String deviceId;
  final int steps;
  final int distanceMeters;
  final double activeKilocalories;

  @override
  List<Object?> get values => [
    start,
    start.plus(duration),
    deviceId,
    steps,
    distanceMeters,
    activeKilocalories,
  ];
}

final class WorkoutRecord extends ExportRecord {
  const new({
    required this.start,
    required this.clientId,
    required this.activityType,
    this.end,
    this.deviceId,
    this.distanceMeters,
    this.activeKilocalories,
  });

  final OffsetTime start;
  final OffsetTime? end;
  final String clientId;
  final String? deviceId;
  final String activityType;
  final double? distanceMeters;
  final double? activeKilocalories;

  @override
  List<Object?> get values => [
    start,
    end,
    clientId,
    deviceId,
    activityType,
    switch (end) {
      null => null,
      final end => (end.utcMs - start.utcMs) ~/ Duration.millisecondsPerSecond,
    },
    distanceMeters,
    activeKilocalories,
  ];
}

@immutable
final class ExportDevice {
  const new({required this.id, required this.name, this.model, this.firmware});

  final String id;
  final String name;
  final String? model;
  final String? firmware;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'model': model,
    'firmware': firmware,
  };
}

@immutable
final class ExportHeader {
  const new({
    required this.exportedAt,
    required this.from,
    required this.to,
    this.device,
  });

  final OffsetTime exportedAt;
  final OffsetTime from;
  final OffsetTime to;
  final ExportDevice? device;
}
