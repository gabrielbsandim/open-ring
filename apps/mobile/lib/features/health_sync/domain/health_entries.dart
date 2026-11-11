import 'package:meta/meta.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:ring_driver/ring_driver.dart';

enum HealthEntryType {
  steps,
  activeEnergy,
  heartRate,
  heartRateSeries,
  spo2,
  hrv,
  sleepSession,
  sleepStage,
  workout,
  workoutHeartRate,
  workoutHeartRateSeries,
}

abstract final class HealthRecordId {
  static const phone = 'phone';

  static String of(String device, HealthEntryType type, DateTime start) =>
      'openring:$device:${type.name}:${start.utcMs}';
}

@immutable
abstract base class HealthValue {
  const new();

  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      other is HealthValue &&
      other.runtimeType == runtimeType &&
      _equalLists(other.props, props);

  @override
  int get hashCode => Object.hash(runtimeType, Object.hashAll(props));

  @override
  String toString() => '$runtimeType$props';

  static bool _equalLists(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final (left, right) = (a[i], b[i]);
      final same = left is List<Object?> && right is List<Object?>
          ? _equalLists(left, right)
          : left == right;
      if (!same) return false;
    }
    return true;
  }
}

sealed class HealthEntry extends HealthValue {
  const new({required this.id, required this.start, required this.end});

  final String id;
  final DateTime start;
  final DateTime end;
}

final class StepsEntry extends HealthEntry {
  const new({
    required super.id,
    required super.start,
    required super.end,
    required this.count,
  });

  final int count;

  @override
  List<Object?> get props => [id, start, end, count];
}

final class ActiveEnergyEntry extends HealthEntry {
  const new({
    required super.id,
    required super.start,
    required super.end,
    required this.kilocalories,
  });

  final double kilocalories;

  @override
  List<Object?> get props => [id, start, end, kilocalories];
}

final class HeartRateEntry extends HealthEntry {
  const new({required super.id, required DateTime at, required this.bpm})
    : super(start: at, end: at);

  final int bpm;

  DateTime get at => start;

  @override
  List<Object?> get props => [id, start, bpm];
}

final class HeartRateSeriesEntry extends HealthEntry {
  const new({
    required super.id,
    required super.start,
    required super.end,
    required this.samples,
  });

  final List<HeartRateEntry> samples;

  @override
  List<Object?> get props => [id, start, end, samples];
}

final class Spo2Entry extends HealthEntry {
  const new({required super.id, required DateTime at, required this.percent})
    : super(start: at, end: at);

  final int percent;

  @override
  List<Object?> get props => [id, start, percent];
}

final class HrvEntry extends HealthEntry {
  const new({
    required super.id,
    required DateTime at,
    required this.milliseconds,
  }) : super(start: at, end: at);

  final int milliseconds;

  @override
  List<Object?> get props => [id, start, milliseconds];
}

final class SleepStageEntry extends HealthValue {
  const new({
    required this.id,
    required this.start,
    required this.end,
    required this.stage,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final SleepStage stage;

  @override
  List<Object?> get props => [id, start, end, stage];
}

final class SleepEntry extends HealthEntry {
  const new({
    required super.id,
    required super.start,
    required super.end,
    required this.stages,
  });

  final List<SleepStageEntry> stages;

  @override
  List<Object?> get props => [id, start, end, stages];
}

final class RoutePoint extends HealthValue {
  const new({
    required this.at,
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
    this.accuracyMeters,
  });

  final DateTime at;
  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final double? accuracyMeters;

  @override
  List<Object?> get props => [
    at,
    latitude,
    longitude,
    altitudeMeters,
    accuracyMeters,
  ];
}

final class WorkoutEntry extends HealthEntry {
  const new({
    required super.id,
    required super.start,
    required super.end,
    required this.activityType,
    this.distanceMeters,
    this.activeKilocalories,
    this.heartRateSeries = const [],
    this.route = const [],
  });

  final String activityType;
  final double? distanceMeters;
  final double? activeKilocalories;
  final List<HeartRateSeriesEntry> heartRateSeries;
  final List<RoutePoint> route;

  List<HeartRateEntry> get heartRate => [
    for (final series in heartRateSeries) ...series.samples,
  ];

  @override
  List<Object?> get props => [
    id,
    start,
    end,
    activityType,
    distanceMeters,
    activeKilocalories,
    heartRateSeries,
    route,
  ];
}

final class HealthWriteBatch extends HealthValue {
  new({
    required this.kind,
    required this.from,
    required this.to,
    required this.version,
    required List<HealthEntry> entries,
  }) : entries = List.unmodifiable(entries);

  final HealthRecordKind kind;
  final DateTime from;
  final DateTime to;
  final int version;
  final List<HealthEntry> entries;

  @override
  List<Object?> get props => [kind, from, to, version, entries];
}
