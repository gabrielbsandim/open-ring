import 'package:meta/meta.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:ring_driver/ring_driver.dart';

typedef ExternalSleepStage = ({DateTime start, DateTime end, SleepStage stage});

@immutable
final class ExternalSleepNight {
  new({
    required this.recordId,
    required this.source,
    required this.start,
    required this.end,
    required this.utcOffset,
    required List<ExternalSleepStage> stages,
  }) : stages = List.unmodifiable(stages);

  final String recordId;
  final String source;
  final DateTime start;
  final DateTime end;
  final Duration utcOffset;
  final List<ExternalSleepStage> stages;

  bool get hasSleep => stages.any((s) => s.stage != SleepStage.awake);
}

@immutable
final class ExternalWorkout {
  const new({
    required this.recordId,
    required this.source,
    required this.activityType,
    required this.start,
    required this.end,
    required this.utcOffset,
  });

  final String recordId;
  final String source;
  final String activityType;
  final DateTime start;
  final DateTime end;
  final Duration utcOffset;

  bool get hasDuration => end.isAfter(start);
}

@immutable
final class ExternalRead<T> {
  const new(this.records, {this.present});

  final List<T> records;

  // Every record id the platform holds in the window, or null when an empty
  // answer cannot be told apart from a failed read.
  final Set<String>? present;
}

abstract interface class HealthReader {
  Future<HealthAccess> readAccess(HealthRecordKind kind);

  Future<bool> requestReadAccess(HealthRecordKind kind);

  Future<bool> backgroundReadAllowed();

  Future<bool> requestBackgroundReadAccess();

  Future<ExternalRead<ExternalSleepNight>> sleepNights({
    required DateTime from,
    required DateTime to,
  });

  Future<ExternalRead<ExternalWorkout>> workouts({
    required DateTime from,
    required DateTime to,
  });
}

final class UnavailableHealthReader implements HealthReader {
  const new();

  @override
  Future<HealthAccess> readAccess(HealthRecordKind kind) async =>
      HealthAccess.unavailable;

  @override
  Future<bool> requestReadAccess(HealthRecordKind kind) async => false;

  @override
  Future<bool> backgroundReadAllowed() async => false;

  @override
  Future<bool> requestBackgroundReadAccess() async => false;

  @override
  Future<ExternalRead<ExternalSleepNight>> sleepNights({
    required DateTime from,
    required DateTime to,
  }) async => const ExternalRead([]);

  @override
  Future<ExternalRead<ExternalWorkout>> workouts({
    required DateTime from,
    required DateTime to,
  }) async => const ExternalRead([]);
}
