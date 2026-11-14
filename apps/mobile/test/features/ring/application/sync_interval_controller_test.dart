import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/domain/sync_scheduler.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';

import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/in_memory_sync_interval_store.dart';
import '../../../helpers/ring_fakes.dart' show FakeSyncStore, fakeRingId;

void main() {
  late FakeSyncScheduler scheduler;

  setUp(() => scheduler = FakeSyncScheduler());

  ProviderContainer containerWith(
    InMemorySyncIntervalStore store, {
    PairedRing? ring = const PairedRing(deviceId: fakeRingId),
  }) => ProviderContainer.test(
    overrides: [
      syncIntervalStoreProvider.overrideWithValue(store),
      syncSchedulerProvider.overrideWithValue(scheduler),
      syncStoreProvider.overrideWithValue(FakeSyncStore(ring: ring)),
    ],
  );

  test('the intervals offered are 15, 30, 60 and 120 minutes', () {
    expect(SyncInterval.values.map((i) => i.minutes), [15, 30, 60, 120]);
  });

  test('defaults to 60 minutes when nothing is saved', () {
    final container = containerWith(InMemorySyncIntervalStore());

    expect(container.read(syncIntervalProvider), SyncInterval.minutes60);
  });

  test('restores the saved interval', () {
    final container = containerWith(
      InMemorySyncIntervalStore(SyncInterval.minutes120),
    );

    expect(container.read(syncIntervalProvider), SyncInterval.minutes120);
  });

  test('ensureScheduled keeps work that is already registered', () async {
    final container = containerWith(
      InMemorySyncIntervalStore(SyncInterval.minutes30),
    );

    await container.read(syncIntervalProvider.notifier).ensureScheduled();

    expect(scheduler.calls, [
      (interval: SyncInterval.minutes30, existing: ExistingSchedule.keep),
    ]);
  });

  test(
    'ensureScheduled without a ring cancels instead of registering',
    () async {
      final container = containerWith(InMemorySyncIntervalStore(), ring: null);

      await container.read(syncIntervalProvider.notifier).ensureScheduled();

      expect(scheduler.calls, isEmpty);
      expect(scheduler.cancels, 1);
    },
  );

  test('select without a ring saves the interval and cancels', () async {
    final store = InMemorySyncIntervalStore();
    final container = containerWith(store, ring: null);

    await container
        .read(syncIntervalProvider.notifier)
        .select(SyncInterval.minutes15);

    expect(store.saved, SyncInterval.minutes15);
    expect(scheduler.calls, isEmpty);
    expect(scheduler.cancels, 1);
  });

  test('select persists the interval and replaces the schedule', () async {
    final store = InMemorySyncIntervalStore();
    final container = containerWith(store);

    await container
        .read(syncIntervalProvider.notifier)
        .select(SyncInterval.minutes15);

    expect(container.read(syncIntervalProvider), SyncInterval.minutes15);
    expect(store.saved, SyncInterval.minutes15);
    expect(scheduler.calls, [
      (interval: SyncInterval.minutes15, existing: ExistingSchedule.replace),
    ]);
  });

  test('selecting the current interval changes nothing', () async {
    final store = InMemorySyncIntervalStore();
    final container = containerWith(store);

    await container
        .read(syncIntervalProvider.notifier)
        .select(SyncInterval.fallback);

    expect(store.writes, 0);
    expect(scheduler.calls, isEmpty);
  });
}
