import 'package:meta/meta.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/domain/ring_sync_batch.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';

@immutable
final class PairedRing {
  const new({
    required this.deviceId,
    this.lastSyncAt,
    this.measurements = AutoMeasurements.allOn,
  });

  final String deviceId;
  final DateTime? lastSyncAt;
  final AutoMeasurements measurements;
}

abstract interface class SyncStore {
  Future<PairedRing?> pairedRing();

  Future<Map<RecordKind, DateTime>> cursors(String deviceId);

  Future<Map<RecordKind, int>> save(RingSyncBatch batch);

  Future<void> advanceCursors(
    String deviceId,
    Map<RecordKind, DateTime> cursors, {
    required DateTime at,
  });

  Future<void> saveMeasurements(String deviceId, AutoMeasurements measurements);

  Future<void> recordRun(String deviceId, SyncRun run);

  Future<List<SyncRun>> recentRuns(String deviceId);

  // Keeps the samples, cursors and log: only the pairing ends.
  Future<void> forget(String deviceId, {required DateTime at});
}
