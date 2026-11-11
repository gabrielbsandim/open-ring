import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/infrastructure/drift_paired_ring_store.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/today/infrastructure/drift_ring_status_reader.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';

void main() {
  test('a saved ring reads as paired and becomes the ring to sync', () async {
    final db = memoryDatabase();
    const ring = RingIdentity(
      deviceId: 'AA:BB:CC:00:00:09',
      name: 'R09_F800',
      model: 'R09',
    );
    expect((await DriftRingStatusReader(db).status()).paired, isFalse);

    await DriftPairedRingStore(db).save(ring, at: DateTime.utc(2026, 11, 10));

    final status = await DriftRingStatusReader(db).status();
    expect(status.paired, isTrue);
    expect(status.name, 'R09_F800');
    expect(status.model, 'R09');
    expect(status.lastSyncAt, isNull);
    expect((await DriftSyncStore(db).pairedRing())?.deviceId, ring.deviceId);
  });

  test('pairing a second ring makes it the current one', () async {
    final db = memoryDatabase();
    final store = DriftPairedRingStore(db);
    await store.save(
      const RingIdentity(deviceId: 'old', name: 'R02_0001', model: 'R02'),
      at: DateTime.utc(2026, 11),
    );

    await store.save(
      const RingIdentity(deviceId: 'new', name: 'R09_F800', model: 'R09'),
      at: DateTime.utc(2026, 11, 10),
    );

    expect((await DriftSyncStore(db).pairedRing())?.deviceId, 'new');
    expect((await DriftRingStatusReader(db).status()).name, 'R09_F800');
  });
}
