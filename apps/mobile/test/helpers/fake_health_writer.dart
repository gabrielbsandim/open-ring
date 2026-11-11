import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';

typedef StoredRecord = ({
  HealthRecordKind kind,
  HealthEntry entry,
  int version,
});

final class FakeHealthWriter implements HealthWriter {
  final Map<String, StoredRecord> platform = {};
  final List<HealthWriteBatch> batches = [];
  final Set<HealthRecordKind> denied = {};
  final Set<HealthRecordKind> deferred = {};
  final List<Set<HealthRecordKind>> requests = [];
  final List<String> inserted = [];
  final List<String> updated = [];
  bool unavailable = false;
  bool grantOnRequest = true;
  int failuresLeft = 0;

  List<HealthEntry> recordsOf(HealthRecordKind kind) => [
    for (final record in platform.values)
      if (record.kind == kind) record.entry,
  ];

  // Heart rate series count by sample, so a test reads what reached the
  // platform rather than how it was grouped.
  List<HealthEntry> entriesOf(HealthRecordKind kind) => [
    for (final entry in recordsOf(kind))
      ...switch (entry) {
        HeartRateSeriesEntry(:final samples) => samples,
        _ => [entry],
      },
  ];

  @override
  Future<HealthAccess> access(HealthRecordKind kind) async {
    if (unavailable) return HealthAccess.unavailable;
    if (deferred.contains(kind)) return HealthAccess.deferred;
    return denied.contains(kind) ? HealthAccess.denied : HealthAccess.granted;
  }

  @override
  Future<bool> requestAccess(Set<HealthRecordKind> kinds) async {
    requests.add(kinds);
    if (grantOnRequest) denied.removeAll(kinds);
    return grantOnRequest;
  }

  @override
  Future<void> replace(HealthWriteBatch batch) async {
    if (failuresLeft > 0) {
      failuresLeft--;
      throw const HealthWriteException('platform busy');
    }
    batches.add(batch);
    final before = {...platform.keys};
    platform.removeWhere(
      (_, record) =>
          record.kind == batch.kind &&
          !record.entry.start.isBefore(batch.from) &&
          record.entry.start.isBefore(batch.to),
    );
    for (final entry in batch.entries) {
      (before.contains(entry.id) ? updated : inserted).add(entry.id);
      platform[entry.id] = (
        kind: batch.kind,
        entry: entry,
        version: batch.version,
      );
    }
  }
}
