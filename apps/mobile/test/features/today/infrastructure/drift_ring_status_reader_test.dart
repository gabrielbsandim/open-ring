import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/today/infrastructure/drift_ring_status_reader.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';

void main() {
  test('without a device the ring is unpaired', () async {
    final status = await DriftRingStatusReader(memoryDatabase()).status();

    expect(status.paired, isFalse);
    expect(status, same(RingStatus.unpaired));
  });

  test('a paired ring that never synced has no sync time', () async {
    final db = await pairedDatabase();

    final status = await DriftRingStatusReader(db).status();

    expect(status.paired, isTrue);
    expect(status.name, 'R09_C0FE');
    expect(status.model, 'R09');
    expect(status.lastSyncAt, isNull);
    expect(status.batteryPercent, isNull);
  });

  test('a sync records time and battery as UTC instants', () async {
    final db = await pairedDatabase();
    final at = DateTime.utc(2026, 11, 10, 8, 40);
    await RingDevicesDao(db).recordSync(
      ringId,
      identity: ringIdentity,
      at: at,
      battery: const BatteryStatus(percent: 68, charging: true),
    );

    final status = await DriftRingStatusReader(db).status();

    expect(status.lastSyncAt, at);
    expect(status.lastSyncAt!.isUtc, isTrue);
    expect(status.batteryPercent, 68);
    expect(status.batteryCharging, isTrue);
    expect(status.batteryAt, at);
  });

  test('the most recently paired ring wins', () async {
    final db = await pairedDatabase(pairedAt: DateTime.utc(2026, 11));
    await RingDevicesDao(db).pair(
      const RingIdentity(
        deviceId: 'R09_BEEF',
        name: 'R09_BEEF',
        firmware: '3.1',
      ),
      at: DateTime.utc(2026, 11, 5),
    );

    final status = await DriftRingStatusReader(db).status();

    expect(status.name, 'R09_BEEF');
    expect(status.firmware, '3.1');
  });

  test('a forgotten ring reads as unpaired', () async {
    final db = await pairedDatabase();
    await RingDevicesDao(db).forget(ringId, at: DateTime.utc(2026, 11, 10));

    final status = await DriftRingStatusReader(db).status();

    expect(status.paired, isFalse);
  });
}
