import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/ring/application/unpair_ring.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/domain/sync_scheduler.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';

import '../../../helpers/fake_health_reader.dart';
import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/ring_fakes.dart';

class FailingScheduler extends FakeSyncScheduler {
  @override
  Future<void> cancel() => throw StateError('no workmanager');
}

class FailingScheduleScheduler extends FakeSyncScheduler {
  @override
  Future<void> schedule(
    SyncInterval interval, {
    ExistingSchedule existing = ExistingSchedule.keep,
  }) => throw StateError('no workmanager');
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

  group('with a Health Connect read left on', () {
    late FakeHealthReader reader;
    late InMemoryHealthReadStore reads;

    setUp(() {
      reader = FakeHealthReader();
      reads = InMemoryHealthReadStore();
    });

    ProviderContainer unpairing(FakeSyncScheduler scheduler) =>
        ProviderContainer.test(
          overrides: [
            ...ringOverrides(
              store: FakeSyncStore(
                ring: const PairedRing(deviceId: fakeRingId),
              ),
              scheduler: scheduler,
            ),
            healthReaderProvider.overrideWithValue(reader),
            healthReadStoreProvider.overrideWithValue(reads),
          ],
        );

    test('criterion 4: a read on and the grant register the job', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      reader.backgroundAllowed = true;
      final scheduler = FakeSyncScheduler();
      final container = unpairing(scheduler);

      final unpaired = await container
          .read(unpairControllerProvider.notifier)
          .unpair();

      expect(unpaired, isTrue);
      expect(scheduler.calls, hasLength(1));
    });

    test('criterion 4: a read on without the grant only cancels', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      final scheduler = FakeSyncScheduler();
      final container = unpairing(scheduler);

      final unpaired = await container
          .read(unpairControllerProvider.notifier)
          .unpair();

      expect(unpaired, isTrue);
      expect(scheduler.calls, isEmpty);
      expect(scheduler.cancels, 1);
    });

    test('criterion 4: no read on only cancels', () async {
      reader.backgroundAllowed = true;
      final scheduler = FakeSyncScheduler();
      final container = unpairing(scheduler);

      await container.read(unpairControllerProvider.notifier).unpair();

      expect(scheduler.calls, isEmpty);
      expect(scheduler.cancels, 1);
    });

    test('a scheduler that fails to register still unpairs', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      reader.backgroundAllowed = true;
      final container = unpairing(FailingScheduleScheduler());

      final unpaired = await container
          .read(unpairControllerProvider.notifier)
          .unpair();

      expect(unpaired, isTrue);
    });
  });
}
