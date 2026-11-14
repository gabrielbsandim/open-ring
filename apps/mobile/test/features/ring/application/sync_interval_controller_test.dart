import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/domain/sync_scheduler.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';

import '../../../helpers/fake_health_reader.dart';
import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/in_memory_sync_interval_store.dart';
import '../../../helpers/ring_fakes.dart' show FakeSyncStore, fakeRingId;

void main() {
  late FakeSyncScheduler scheduler;
  late FakeHealthReader reader;
  late InMemoryHealthReadStore reads;

  setUp(() {
    scheduler = FakeSyncScheduler();
    reader = FakeHealthReader();
    reads = InMemoryHealthReadStore();
  });

  ProviderContainer containerWith(
    InMemorySyncIntervalStore store, {
    PairedRing? ring = const PairedRing(deviceId: fakeRingId),
  }) => ProviderContainer.test(
    overrides: [
      syncIntervalStoreProvider.overrideWithValue(store),
      syncSchedulerProvider.overrideWithValue(scheduler),
      syncStoreProvider.overrideWithValue(FakeSyncStore(ring: ring)),
      healthReaderProvider.overrideWithValue(reader),
      healthReadStoreProvider.overrideWithValue(reads),
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

  group('without a ring', () {
    test('criterion 1: a read on and the grant register the job', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      reader.backgroundAllowed = true;
      final container = containerWith(
        InMemorySyncIntervalStore(SyncInterval.minutes30),
        ring: null,
      );

      await container.read(syncIntervalProvider.notifier).ensureScheduled();

      expect(scheduler.calls, [
        (interval: SyncInterval.minutes30, existing: ExistingSchedule.keep),
      ]);
      expect(scheduler.cancels, 0);
    });

    test('criterion 1: a workout read alone registers the job', () async {
      await reads.setEnabled(HealthRecordKind.workout, enabled: true);
      reader.backgroundAllowed = true;
      final container = containerWith(InMemorySyncIntervalStore(), ring: null);

      await container.read(syncIntervalProvider.notifier).ensureScheduled();

      expect(scheduler.calls, hasLength(1));
      expect(scheduler.cancels, 0);
    });

    test('criterion 1: a read on without the grant cancels', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      reader.backgroundAllowed = false;
      final container = containerWith(InMemorySyncIntervalStore(), ring: null);

      await container.read(syncIntervalProvider.notifier).ensureScheduled();

      expect(reader.backgroundChecks, 1);
      expect(scheduler.calls, isEmpty);
      expect(scheduler.cancels, 1);
    });

    test('criterion 1: the grant with both reads off cancels', () async {
      reader.backgroundAllowed = true;
      final container = containerWith(InMemorySyncIntervalStore(), ring: null);

      await container.read(syncIntervalProvider.notifier).ensureScheduled();

      expect(scheduler.calls, isEmpty);
      expect(scheduler.cancels, 1);
    });

    test('criterion 1: select saves and replaces the job on a grant', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      reader.backgroundAllowed = true;
      final store = InMemorySyncIntervalStore();
      final container = containerWith(store, ring: null);

      await container
          .read(syncIntervalProvider.notifier)
          .select(SyncInterval.minutes15);

      expect(store.saved, SyncInterval.minutes15);
      expect(scheduler.calls, [
        (interval: SyncInterval.minutes15, existing: ExistingSchedule.replace),
      ]);
    });

    test('a background check that throws cancels', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      reader.backgroundCheck = () async =>
          throw StateError('no Health Connect');
      final container = containerWith(InMemorySyncIntervalStore(), ring: null);

      await container.read(syncIntervalProvider.notifier).ensureScheduled();

      expect(scheduler.calls, isEmpty);
      expect(scheduler.cancels, 1);
    });

    testWidgets('a background check that hangs cancels at the import limit', (
      tester,
    ) async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      reader.backgroundCheck = () => Completer<bool>().future;
      final container = containerWith(InMemorySyncIntervalStore(), ring: null);
      var done = false;

      unawaited(
        container
            .read(syncIntervalProvider.notifier)
            .ensureScheduled()
            .then((_) => done = true),
      );
      await tester.pump(ringlessImportLimit + const Duration(seconds: 1));

      expect(done, isTrue);
      expect(scheduler.calls, isEmpty);
      expect(scheduler.cancels, 1);
    });
  });

  test(
    'criterion 1: a paired ring schedules without asking the reader',
    () async {
      reader.backgroundAllowed = false;
      final container = containerWith(InMemorySyncIntervalStore());

      await container.read(syncIntervalProvider.notifier).ensureScheduled();

      expect(reader.backgroundChecks, 0);
      expect(scheduler.calls, hasLength(1));
      expect(scheduler.cancels, 0);
    },
  );
}
