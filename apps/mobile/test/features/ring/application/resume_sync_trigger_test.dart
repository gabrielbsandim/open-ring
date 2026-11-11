import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/application/resume_sync_trigger.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';

import '../../../helpers/database.dart';
import '../../../helpers/sync_fixtures.dart';

class FakeClock {
  new(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

void main() {
  const interval = ResumeSyncTrigger.defaultMinimumInterval;
  late FakeClock clock;
  late int syncs;
  late PairedRing? ring;

  setUp(() {
    clock = FakeClock(syncNow);
    syncs = 0;
    ring = const PairedRing(deviceId: ringId);
  });

  ResumeSyncTrigger trigger() => ResumeSyncTrigger(
    pairedRing: () async => ring,
    sync: () async => syncs++,
    clock: clock.call,
  );

  test('the minimum interval is 15 minutes', () {
    expect(interval, const Duration(minutes: 15));
  });

  test('syncs on the first foreground', () async {
    await trigger().onForeground();

    expect(syncs, 1);
  });

  test('ignores a resume inside the minimum interval', () async {
    final resume = trigger();
    await resume.onForeground();

    clock.advance(interval - const Duration(seconds: 1));
    await resume.onForeground();

    expect(syncs, 1);
  });

  test('syncs again once the minimum interval has passed', () async {
    final resume = trigger();
    await resume.onForeground();

    clock.advance(interval);
    await resume.onForeground();

    expect(syncs, 2);
  });

  test('two resumes at the same instant sync once', () async {
    final resume = trigger();

    await Future.wait([resume.onForeground(), resume.onForeground()]);

    expect(syncs, 1);
  });

  test('skips when the ring synced recently in the background', () async {
    ring = PairedRing(
      deviceId: ringId,
      lastSyncAt: syncNow.subtract(const Duration(minutes: 5)),
    );

    await trigger().onForeground();

    expect(syncs, 0);
  });

  test('syncs when the last ring sync is older than the interval', () async {
    ring = PairedRing(deviceId: ringId, lastSyncAt: syncNow.subtract(interval));

    await trigger().onForeground();

    expect(syncs, 1);
  });

  test('does nothing without a paired ring', () async {
    ring = null;

    await trigger().onForeground();

    expect(syncs, 0);
  });

  test('an app resume runs a ring sync through the controller', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final db = await pairedDatabase();
    final driver = loadedDriver();
    final container = ProviderContainer.test(
      overrides: [
        syncStoreProvider.overrideWithValue(DriftSyncStore(db)),
        syncLockProvider.overrideWithValue(SyncLocksDao(db)),
        smartRingDriverProvider.overrideWithValue(driver),
        syncClockProvider.overrideWithValue(() => syncNow),
      ],
    );
    final synced = Completer<void>();
    container
      ..listen(ringSyncProvider, (_, next) {
        if (next.lastSuccessAt == null || synced.isCompleted) return;
        synced.complete();
      })
      ..read(resumeSyncTriggerProvider);

    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await synced.future.timeout(const Duration(seconds: 5));

    expect(driver.connects, 1);
    expect(container.read(ringSyncProvider).lastSuccessAt, syncNow);
  });

  test(
    'losing the lock to a background sync on resume shows no error',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final db = await pairedDatabase();
      final driver = loadedDriver();
      final container = ProviderContainer.test(
        overrides: [
          syncStoreProvider.overrideWithValue(DriftSyncStore(db)),
          syncLockProvider.overrideWithValue(SyncLocksDao(db)),
          smartRingDriverProvider.overrideWithValue(driver),
          syncClockProvider.overrideWithValue(() => syncNow),
        ],
      );
      await SyncLocksDao(db).acquire(
        'background',
        at: syncNow,
        timeout: const Duration(minutes: 10),
      );

      await container.read(resumeSyncTriggerProvider).onForeground();

      final sync = container.read(ringSyncProvider);
      expect(sync.lastError, isNull);
      expect(sync.syncing, isFalse);
      expect(driver.calls, isEmpty);
    },
  );
}
