import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/sync_scheduler.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';

final class UnpairRing {
  const new({
    required this.store,
    required this.scheduler,
    required this.clock,
    this.reschedule,
  });

  final SyncStore store;
  final SyncScheduler scheduler;
  final DateTime Function() clock;
  final Future<void> Function()? reschedule;

  Future<bool> call() async {
    final ring = await store.pairedRing();
    if (ring == null) return false;
    await store.forget(ring.deviceId, at: clock());
    await _updateSchedule();
    return true;
  }

  // A worker left scheduled finds no paired ring and ends without a sync;
  // a Health Connect read allowed in the background keeps it registered.
  Future<void> _updateSchedule() async {
    try {
      await (reschedule ?? scheduler.cancel)();
    } on Object {
      return;
    }
  }
}

final unpairRingProvider = Provider<UnpairRing>(
  (ref) => UnpairRing(
    store: ref.watch(syncStoreProvider),
    scheduler: ref.watch(syncSchedulerProvider),
    clock: ref.watch(syncClockProvider),
    reschedule: () => ref.read(syncIntervalProvider.notifier).ensureScheduled(),
  ),
);

final NotifierProvider<UnpairController, bool> unpairControllerProvider =
    NotifierProvider.autoDispose(UnpairController.new);

class UnpairController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<bool> unpair() async {
    if (state) return false;
    state = true;
    final revision = ref.read(dataRevisionProvider.notifier);
    final unpaired = await _run();
    if (unpaired) revision.bump();
    if (!ref.mounted) return unpaired;
    state = false;
    if (unpaired) ref.invalidate(ringSyncProvider);
    return unpaired;
  }

  Future<bool> _run() async {
    try {
      return await ref.read(unpairRingProvider)();
    } on Object {
      return false;
    }
  }
}
