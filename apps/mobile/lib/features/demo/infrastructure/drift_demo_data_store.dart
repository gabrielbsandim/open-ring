import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/demo/domain/demo_data.dart';
import 'package:open_ring/features/demo/domain/demo_data_store.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:open_ring/features/ring/infrastructure/ring_samples_dao.dart';
import 'package:open_ring/features/ring/infrastructure/sleep_dao.dart';
import 'package:open_ring/features/ring/infrastructure/sync_runs_dao.dart';
import 'package:open_ring/features/workout/infrastructure/workouts_dao.dart';

// Writes through the DAOs directly rather than the sync and workout stores,
// because those also enqueue every write for Health Connect.
final class DriftDemoDataStore implements DemoDataStore {
  new(this._db)
    : _devices = RingDevicesDao(_db),
      _samples = RingSamplesDao(_db),
      _sleep = SleepDao(_db),
      _runs = SyncRunsDao(_db),
      _workouts = WorkoutsDao(_db);

  final AppDatabase _db;
  final RingDevicesDao _devices;
  final RingSamplesDao _samples;
  final SleepDao _sleep;
  final SyncRunsDao _runs;
  final WorkoutsDao _workouts;

  @override
  Future<void> replace(DemoData data) => _db.transaction(() async {
    await _delete(data.deviceId);
    final id = data.deviceId;
    await _devices.pair(data.identity, at: data.pairedAt);
    await _devices.recordSync(
      id,
      identity: data.identity,
      battery: data.battery,
      at: data.syncedAt,
    );
    await _samples.upsertActivity(id, data.activity);
    await _samples.upsertHeartRate(id, data.heartRate);
    await _samples.upsertHrv(id, data.hrv);
    await _samples.upsertSpo2(id, data.spo2);
    await _samples.upsertStress(id, data.stress);
    await _sleep.replaceNights(id, data.sleep);
    for (final workout in data.workouts) {
      await _workouts.insertFinished(workout, deviceId: id);
    }
    for (final run in data.syncRuns) {
      await _runs.record(id, run);
    }
  });

  @override
  Future<void> wipe() => _db.transaction(() => _delete(demoDeviceId));

  // Children before the device row: every sample table references it.
  Future<void> _delete(String deviceId) async {
    final tables = <TableInfo<Table, Object?>>[
      _db.activityBuckets,
      _db.hrSamples,
      _db.hrvSamples,
      _db.spo2Samples,
      _db.stressSamples,
      _db.sleepSegments,
      _db.sleepSessions,
      _db.syncCursors,
      _db.syncRuns,
      _db.healthOutbox,
      _db.workouts,
      _db.ringDevices,
    ];
    for (final table in tables) {
      await _db.customUpdate(
        'DELETE FROM ${table.actualTableName} WHERE device_id = ?',
        variables: [Variable.withString(deviceId)],
        updates: {table},
        updateKind: UpdateKind.delete,
      );
    }
  }
}
