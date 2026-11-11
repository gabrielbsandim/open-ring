import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';

// Deferred: granted, but this engine may not use it yet (a background read
// without READ_HEALTH_DATA_IN_BACKGROUND), so it waits for the next run.
enum HealthAccess { granted, denied, unavailable, deferred }

final class HealthWriteException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'HealthWriteException: $message';
}

abstract interface class HealthWriter {
  Future<HealthAccess> access(HealthRecordKind kind);

  Future<bool> requestAccess(Set<HealthRecordKind> kinds);

  // After a replace the platform holds exactly the batch entries among the
  // OpenRing records of that kind starting in [from, to), so a re-send updates.
  Future<void> replace(HealthWriteBatch batch);
}

final class UnavailableHealthWriter implements HealthWriter {
  const new();

  @override
  Future<HealthAccess> access(HealthRecordKind kind) async =>
      HealthAccess.unavailable;

  @override
  Future<bool> requestAccess(Set<HealthRecordKind> kinds) async => false;

  @override
  Future<void> replace(HealthWriteBatch batch) async =>
      throw const HealthWriteException('No health platform in this mode.');
}
