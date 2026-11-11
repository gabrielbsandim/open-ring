import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/ring/application/unpair_ring.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';

import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/ring_fakes.dart';

class FailingScheduler extends FakeSyncScheduler {
  @override
  Future<void> cancel() => throw StateError('no workmanager');
}

void main() {
  final at = DateTime(2026, 11, 10, 8);

  test('forgets the ring and cancels the background sync', () async {
    final store = FakeSyncStore(ring: const PairedRing(deviceId: fakeRingId));
    final scheduler = FakeSyncScheduler();

    final unpaired = await UnpairRing(
      store: store,
      scheduler: scheduler,
      clock: () => at,
    )();

    expect(unpaired, isTrue);
    expect(store.forgotten, [fakeRingId]);
    expect(store.ring, isNull);
    expect(scheduler.cancels, 1);
  });

  test('a failed cancel still unpairs', () async {
    final store = FakeSyncStore(ring: const PairedRing(deviceId: fakeRingId));

    final unpaired = await UnpairRing(
      store: store,
      scheduler: FailingScheduler(),
      clock: () => at,
    )();

    expect(unpaired, isTrue);
    expect(store.forgotten, [fakeRingId]);
  });

  test('without a paired ring there is nothing to cancel', () async {
    final scheduler = FakeSyncScheduler();

    final unpaired = await UnpairRing(
      store: FakeSyncStore(),
      scheduler: scheduler,
      clock: () => at,
    )();

    expect(unpaired, isFalse);
    expect(scheduler.cancels, 0);
  });

  test('the controller bumps the data revision once it unpaired', () async {
    final store = FakeSyncStore(ring: const PairedRing(deviceId: fakeRingId));
    final container = ProviderContainer.test(
      overrides: ringOverrides(store: store),
    );
    final before = container.read(dataRevisionProvider);

    final unpaired = await container
        .read(unpairControllerProvider.notifier)
        .unpair();

    expect(unpaired, isTrue);
    expect(container.read(dataRevisionProvider), before + 1);
    expect(container.read(unpairControllerProvider), isFalse);
  });

  test('the controller reports a store failure without a bump', () async {
    final store = FakeSyncStore(ring: const PairedRing(deviceId: fakeRingId))
      ..forgetError = Exception('disk full');
    final container = ProviderContainer.test(
      overrides: ringOverrides(store: store),
    );
    final before = container.read(dataRevisionProvider);

    final unpaired = await container
        .read(unpairControllerProvider.notifier)
        .unpair();

    expect(unpaired, isFalse);
    expect(container.read(dataRevisionProvider), before);
  });
}
