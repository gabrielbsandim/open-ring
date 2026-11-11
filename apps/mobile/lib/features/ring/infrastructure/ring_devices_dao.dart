import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/tables/ring_tables.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:ring_driver/ring_driver.dart';

part 'ring_devices_dao.g.dart';

@DriftAccessor(tables: [RingDevices])
class RingDevicesDao extends DatabaseAccessor<AppDatabase>
    with _$RingDevicesDaoMixin {
  new(super.attachedDatabase);

  Future<void> pair(RingIdentity identity, {required DateTime at}) =>
      into(ringDevices).insert(
        RingDevicesCompanion.insert(
          deviceId: identity.deviceId,
          name: identity.name,
          model: Value(identity.model),
          firmware: Value(identity.firmware),
          pairedAtUtcMs: at.utcMs,
        ),
        onConflict: DoUpdate(
          (old) => RingDevicesCompanion(
            name: Value(identity.name),
            model: Value(identity.model),
            firmware: Value(identity.firmware),
            pairedAtUtcMs: Value(at.utcMs),
            unpairedAtUtcMs: const Value(null),
          ),
        ),
      );

  Future<PairedRing?> latestPaired() async {
    final row =
        await (select(ringDevices)
              ..where((d) => d.unpairedAtUtcMs.isNull())
              ..orderBy([(d) => OrderingTerm.desc(d.pairedAtUtcMs)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return PairedRing(
      deviceId: row.deviceId,
      lastSyncAt: switch (row.lastSyncAtUtcMs) {
        null => null,
        final ms => fromUtcMs(ms),
      },
      measurements: AutoMeasurements(
        off: {
          if (!row.autoHeartRate) AutoMeasurement.heartRate,
          if (!row.autoSpo2) AutoMeasurement.spo2,
          if (!row.autoStress) AutoMeasurement.stress,
          if (!row.autoHrv) AutoMeasurement.hrv,
        },
      ),
    );
  }

  Future<void> saveMeasurements(
    String deviceId,
    AutoMeasurements measurements,
  ) => (update(ringDevices)..where((d) => d.deviceId.equals(deviceId))).write(
    RingDevicesCompanion(
      autoHeartRate: Value(measurements.isOn(AutoMeasurement.heartRate)),
      autoSpo2: Value(measurements.isOn(AutoMeasurement.spo2)),
      autoStress: Value(measurements.isOn(AutoMeasurement.stress)),
      autoHrv: Value(measurements.isOn(AutoMeasurement.hrv)),
    ),
  );

  Future<void> forget(String deviceId, {required DateTime at}) =>
      (update(ringDevices)..where((d) => d.deviceId.equals(deviceId))).write(
        RingDevicesCompanion(unpairedAtUtcMs: Value(at.utcMs)),
      );

  Future<RingDeviceRow?> find(String deviceId) => (select(
    ringDevices,
  )..where((d) => d.deviceId.equals(deviceId))).getSingleOrNull();

  Future<void> recordSync(
    String deviceId, {
    required RingIdentity identity,
    required DateTime at,
    BatteryStatus? battery,
  }) {
    final model = Value.absentIfNull(identity.model);
    final firmware = Value.absentIfNull(identity.firmware);
    final percent = Value.absentIfNull(battery?.percent);
    final charging = Value.absentIfNull(battery?.charging);
    final batteryAt = Value.absentIfNull(battery == null ? null : at.utcMs);
    return into(ringDevices).insert(
      RingDevicesCompanion.insert(
        deviceId: deviceId,
        name: identity.name,
        model: model,
        firmware: firmware,
        pairedAtUtcMs: at.utcMs,
        lastSyncAtUtcMs: Value(at.utcMs),
        batteryPercent: percent,
        batteryCharging: charging,
        batteryAtUtcMs: batteryAt,
      ),
      onConflict: DoUpdate(
        (old) => RingDevicesCompanion(
          model: model,
          firmware: firmware,
          lastSyncAtUtcMs: Value(at.utcMs),
          batteryPercent: percent,
          batteryCharging: charging,
          batteryAtUtcMs: batteryAt,
        ),
      ),
    );
  }
}
