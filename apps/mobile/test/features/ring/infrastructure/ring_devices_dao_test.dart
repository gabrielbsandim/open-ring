import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:open_ring/features/ring/infrastructure/ring_samples_dao.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';
import '../../../helpers/sync_fixtures.dart';

void main() {
  const syncIdentity = RingIdentity(
    deviceId: ringId,
    name: 'COLMI R09',
    model: 'R09',
  );

  test('no ring is paired on a fresh database', () async {
    expect(await RingDevicesDao(memoryDatabase()).latestPaired(), isNull);
  });

  test('the latest pairing wins', () async {
    final db = await pairedDatabase(pairedAt: DateTime(2026, 11));
    final dao = RingDevicesDao(db);
    await dao.pair(
      const RingIdentity(deviceId: 'R09_BEEF', name: 'R09_BEEF'),
      at: DateTime(2026, 11, 5),
    );

    final paired = await dao.latestPaired();

    expect(paired?.deviceId, 'R09_BEEF');
    expect(paired?.lastSyncAt, isNull);
  });

  test('recordSync keeps the pairing and stores battery and time', () async {
    final pairedAt = DateTime(2026, 11);
    final dao = RingDevicesDao(await pairedDatabase(pairedAt: pairedAt));

    await dao.recordSync(
      ringId,
      identity: syncIdentity,
      battery: const BatteryStatus(percent: 64, charging: true),
      at: syncNow,
    );

    final row = await dao.find(ringId);
    expect(row?.name, ringIdentity.name);
    expect(row?.pairedAtUtcMs, pairedAt.millisecondsSinceEpoch);
    expect(row?.lastSyncAtUtcMs, syncNow.millisecondsSinceEpoch);
    expect(row?.batteryPercent, 64);
    expect(row?.batteryCharging, isTrue);
    expect((await dao.latestPaired())?.lastSyncAt, syncNow);
  });

  test('a sync without a battery reading keeps the previous one', () async {
    final dao = RingDevicesDao(await pairedDatabase());
    await dao.recordSync(
      ringId,
      identity: syncIdentity,
      battery: const BatteryStatus(percent: 64, charging: false),
      at: syncNow,
    );
    final later = syncNow.add(const Duration(hours: 1));

    await dao.recordSync(ringId, identity: syncIdentity, at: later);

    final row = await dao.find(ringId);
    expect(row?.batteryPercent, 64);
    expect(row?.batteryAtUtcMs, syncNow.millisecondsSinceEpoch);
    expect(row?.lastSyncAtUtcMs, later.millisecondsSinceEpoch);
  });

  test('recordSync registers a ring it has not seen', () async {
    final dao = RingDevicesDao(memoryDatabase());

    await dao.recordSync(ringId, identity: syncIdentity, at: syncNow);

    final row = await dao.find(ringId);
    expect(row?.pairedAtUtcMs, syncNow.millisecondsSinceEpoch);
    expect(row?.batteryPercent, isNull);
  });

  test('a forgotten ring is no longer paired and keeps its samples', () async {
    final db = await pairedDatabase();
    final dao = RingDevicesDao(db);
    await RingSamplesDao(db)
        .upsertHeartRate(ringId, [HeartRateSample(at: syncNow, bpm: 61)]);

    await dao.forget(ringId, at: syncNow);

    expect(await dao.latestPaired(), isNull);
    expect(await rowCount(db, 'hr_samples'), 1);
    expect((await dao.find(ringId))?.unpairedAtUtcMs, isNotNull);
  });

  test('pairing a forgotten ring again makes it the paired ring', () async {
    final db = await pairedDatabase();
    final dao = RingDevicesDao(db);
    await dao.forget(ringId, at: syncNow);

    await dao.pair(ringIdentity, at: syncNow.add(const Duration(hours: 1)));

    expect((await dao.latestPaired())?.deviceId, ringId);
  });

  test('measurements start on and keep what the user turned off', () async {
    final dao = RingDevicesDao(await pairedDatabase());
    expect((await dao.latestPaired())?.measurements, AutoMeasurements.allOn);

    const choice = AutoMeasurements(
      off: {AutoMeasurement.heartRate, AutoMeasurement.hrv},
    );
    await dao.saveMeasurements(ringId, choice);

    expect((await dao.latestPaired())?.measurements, choice);
  });
}
