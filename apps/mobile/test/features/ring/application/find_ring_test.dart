import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/application/find_ring.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';

import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/ring_fakes.dart';

void main() {
  late FakeRingDriver driver;
  late InMemorySyncLock lock;
  late FakeSyncStore store;

  setUp(() {
    driver = FakeRingDriver();
    lock = InMemorySyncLock();
    store = FakeSyncStore(ring: const PairedRing(deviceId: fakeRingId));
  });

  FindRing finder() => FindRing(
    driver: driver,
    store: store,
    lock: lock,
    clock: () => DateTime(2026, 11, 10, 8),
    newOwner: () => 'finder',
  );

  test('lights the ring, then hangs up and frees the lock', () async {
    expect(await finder()(), FindRingPhase.lit);

    expect(driver.calls, ['connect', 'findDevice', 'disconnect']);
    expect(lock.holder, isNull);
    expect(lock.releases, 1);
  });

  test('waits out a running sync instead of connecting', () async {
    lock.holder = 'sync';

    expect(await finder()(), FindRingPhase.busy);
    expect(driver.connects, 0);
    expect(lock.holder, 'sync');
  });

  test('a ring out of reach fails and still frees the lock', () async {
    driver.connectError = StateError('GATT_ERROR 133');

    expect(await finder()(), FindRingPhase.failed);
    expect(driver.calls, isNot(contains('findDevice')));
    expect(lock.holder, isNull);
  });

  test('a rejected command fails and hangs up', () async {
    driver.findError = StateError('nope');

    expect(await finder()(), FindRingPhase.failed);
    expect(driver.disconnects, 1);
  });

  test('without a paired ring it fails without touching the ring', () async {
    store.ring = null;

    expect(await finder()(), FindRingPhase.failed);
    expect(driver.calls, isEmpty);
  });
}
