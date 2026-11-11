import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/domain/sync_lock.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:ring_driver/ring_driver.dart';

enum FindRingPhase { idle, finding, lit, busy, failed }

final class FindRing {
  const new({
    required this.driver,
    required this.store,
    required this.lock,
    required this.clock,
    this.newOwner = randomLockOwner,
  });

  final SmartRingDriver driver;
  final SyncStore store;
  final SyncLock lock;
  final DateTime Function() clock;
  final String Function() newOwner;

  Future<FindRingPhase> call() async {
    final ring = await store.pairedRing();
    if (ring == null) return FindRingPhase.failed;
    final owner = newOwner();
    final acquired = await lock.acquire(
      owner,
      at: clock(),
      timeout: SyncPairedRing.defaultLockTimeout,
    );
    if (!acquired) return FindRingPhase.busy;
    try {
      await driver.connect(ring.deviceId);
      await driver.findDevice();
      return FindRingPhase.lit;
    } on Object {
      return FindRingPhase.failed;
    } finally {
      await _disconnect();
      await lock.release(owner);
    }
  }

  Future<void> _disconnect() async {
    try {
      await driver.disconnect();
    } on Object {
      return;
    }
  }
}

final findRingProvider = Provider<FindRing>(
  (ref) => FindRing(
    driver: ref.watch(smartRingDriverProvider),
    store: ref.watch(syncStoreProvider),
    lock: ref.watch(syncLockProvider),
    clock: ref.watch(syncClockProvider),
  ),
);

final NotifierProvider<FindRingController, FindRingPhase>
findRingControllerProvider = NotifierProvider.autoDispose(
  FindRingController.new,
);

class FindRingController extends Notifier<FindRingPhase> {
  @override
  FindRingPhase build() => FindRingPhase.idle;

  Future<void> find() async {
    if (state == FindRingPhase.finding) return;
    state = FindRingPhase.finding;
    final phase = await ref.read(findRingProvider)();
    if (!ref.mounted) return;
    state = phase;
  }
}
