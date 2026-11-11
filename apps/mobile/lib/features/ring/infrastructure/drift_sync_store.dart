import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/domain/ring_sync_batch.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:open_ring/features/ring/infrastructure/ring_samples_dao.dart';
import 'package:open_ring/features/ring/infrastructure/sleep_dao.dart';
import 'package:open_ring/features/ring/infrastructure/sync_cursors_dao.dart';
import 'package:open_ring/features/ring/infrastructure/sync_runs_dao.dart';
import 'package:open_ring/features/ring/infrastructure/write_summary.dart';

final class DriftSyncStore implements SyncStore {
  new(
    this._db, {
    RingDevicesDao? devices,
    SyncCursorsDao? cursors,
    RingSamplesDao? samples,
    SleepDao? sleep,
    HealthOutboxDao? outbox,
    SyncRunsDao? runs,
  }) : _devices = devices ?? RingDevicesDao(_db),
       _cursors = cursors ?? SyncCursorsDao(_db),
       _samples = samples ?? RingSamplesDao(_db),
       _sleep = sleep ?? SleepDao(_db),
       _outbox = outbox ?? HealthOutboxDao(_db),
       _runs = runs ?? SyncRunsDao(_db);

  final AppDatabase _db;
  final RingDevicesDao _devices;
  final SyncCursorsDao _cursors;
  final RingSamplesDao _samples;
  final SleepDao _sleep;
  final HealthOutboxDao _outbox;
  final SyncRunsDao _runs;

  @override
  Future<PairedRing?> pairedRing() => _devices.latestPaired();

  @override
  Future<Map<RecordKind, DateTime>> cursors(String deviceId) =>
      _cursors.cursorsFor(deviceId);

  @override
  Future<Map<RecordKind, int>> save(RingSyncBatch batch) =>
      _db.transaction(() async {
        final id = batch.deviceId;
        await _devices.recordSync(
          id,
          identity: batch.identity,
          battery: batch.battery,
          at: batch.syncedAt,
        );
        final writes = <RecordKind, Future<WriteSummary> Function()>{
          if (batch.activity case final rows?)
            RecordKind.activity: () => _samples.upsertActivity(id, rows),
          if (batch.heartRate case final rows?)
            RecordKind.heartRate: () => _samples.upsertHeartRate(id, rows),
          if (batch.spo2 case final rows?)
            RecordKind.spo2: () => _samples.upsertSpo2(id, rows),
          if (batch.stress case final rows?)
            RecordKind.stress: () => _samples.upsertStress(id, rows),
          if (batch.hrv case final rows?)
            RecordKind.hrv: () => _samples.upsertHrv(id, rows),
          if (batch.sleep case final rows?)
            RecordKind.sleep: () => _sleep.replaceNights(id, rows),
        };
        final counts = <RecordKind, int>{};
        for (final MapEntry(key: kind, value: write) in writes.entries) {
          final summary = await write();
          counts[kind] = summary.count;
          await _enqueue(kind, batch, summary);
        }
        return counts;
      });

  @override
  Future<void> advanceCursors(
    String deviceId,
    Map<RecordKind, DateTime> cursors, {
    required DateTime at,
  }) => _cursors.advance(deviceId, cursors, at: at);

  @override
  Future<void> saveMeasurements(
    String deviceId,
    AutoMeasurements measurements,
  ) => _devices.saveMeasurements(deviceId, measurements);

  @override
  Future<void> recordRun(String deviceId, SyncRun run) =>
      _runs.record(deviceId, run);

  @override
  Future<List<SyncRun>> recentRuns(String deviceId) => _runs.recent(deviceId);

  @override
  Future<void> forget(String deviceId, {required DateTime at}) =>
      _devices.forget(deviceId, at: at);

  Future<void> _enqueue(
    RecordKind kind,
    RingSyncBatch batch,
    WriteSummary summary,
  ) async {
    final (from, to) = (summary.from, summary.to);
    if (from == null || to == null) return;
    await _outbox.enqueue(
      kind: kind,
      deviceId: batch.deviceId,
      from: from,
      to: to,
      recordCount: summary.count,
      at: batch.syncedAt,
    );
  }
}
