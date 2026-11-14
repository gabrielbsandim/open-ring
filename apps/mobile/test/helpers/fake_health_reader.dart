import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:ring_driver/ring_driver.dart';

typedef ReadWindow = ({DateTime from, DateTime to});

final class FakeHealthReader implements HealthReader {
  new({
    this.access = HealthAccess.denied,
    this.grantOnRequest = true,
    List<ExternalSleepNight>? nights,
    List<ExternalWorkout>? sessions,
    this.complete = true,
  }) : nights = nights ?? [],
       sessions = sessions ?? [];

  HealthAccess access;
  bool grantOnRequest;
  List<ExternalSleepNight> nights;
  List<ExternalWorkout> sessions;

  // False reads like the plugin after a failure: an answer that cannot
  // prove a record is gone.
  bool complete;
  final List<HealthRecordKind> requests = [];
  final List<ReadWindow> reads = [];
  Object? sleepError;

  bool backgroundAllowed = false;
  bool grantBackgroundOnRequest = true;
  Future<bool> Function()? backgroundCheck;
  int backgroundChecks = 0;
  int backgroundRequests = 0;

  @override
  Future<bool> backgroundReadAllowed() {
    backgroundChecks++;
    return backgroundCheck?.call() ?? Future.value(backgroundAllowed);
  }

  @override
  Future<bool> requestBackgroundReadAccess() async {
    backgroundRequests++;
    if (grantBackgroundOnRequest) backgroundAllowed = true;
    return grantBackgroundOnRequest;
  }

  @override
  Future<HealthAccess> readAccess(HealthRecordKind kind) async => access;

  @override
  Future<bool> requestReadAccess(HealthRecordKind kind) async {
    requests.add(kind);
    if (grantOnRequest) access = HealthAccess.granted;
    return grantOnRequest;
  }

  @override
  Future<ExternalRead<ExternalSleepNight>> sleepNights({
    required DateTime from,
    required DateTime to,
  }) async {
    reads.add((from: from, to: to));
    if (sleepError case final error?) throw error;
    return _read(nights, [for (final night in nights) night.recordId]);
  }

  @override
  Future<ExternalRead<ExternalWorkout>> workouts({
    required DateTime from,
    required DateTime to,
  }) async {
    reads.add((from: from, to: to));
    return _read(sessions, [for (final session in sessions) session.recordId]);
  }

  ExternalRead<T> _read<T>(List<T> records, List<String> ids) =>
      ExternalRead(records, present: complete ? ids.toSet() : null);
}

// A night of light sleep with one REM block, from [start] for [hours].
ExternalSleepNight externalNight(
  String source,
  DateTime start, {
  String? id,
  int hours = 7,
  List<ExternalSleepStage>? stages,
}) {
  final end = start.add(Duration(hours: hours));
  final rem = end.subtract(const Duration(hours: 1));
  return ExternalSleepNight(
    recordId: id ?? '$source:${start.millisecondsSinceEpoch}',
    source: source,
    start: start,
    end: end,
    utcOffset: Duration.zero,
    stages:
        stages ??
        [
          (start: start, end: rem, stage: SleepStage.light),
          (start: rem, end: end, stage: SleepStage.rem),
        ],
  );
}

// A workout another app wrote, from [start] for [minutes].
ExternalWorkout externalWorkout(
  String source,
  DateTime start, {
  String? id,
  int minutes = 40,
  String activityType = 'running',
}) => ExternalWorkout(
  recordId: id ?? '$source:${start.millisecondsSinceEpoch}',
  source: source,
  activityType: activityType,
  start: start,
  end: start.add(Duration(minutes: minutes)),
  utcOffset: Duration.zero,
);
