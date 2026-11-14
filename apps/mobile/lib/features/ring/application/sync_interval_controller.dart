import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/health_sync/application/enable_background_reads.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/domain/sync_interval_store.dart';
import 'package:open_ring/features/ring/domain/sync_scheduler.dart';

final syncSchedulerProvider = Provider<SyncScheduler>(
  (ref) => throw UnimplementedError('Override syncSchedulerProvider.'),
);

final syncIntervalStoreProvider = Provider<SyncIntervalStore>(
  (ref) => throw UnimplementedError('Override syncIntervalStoreProvider.'),
);

final syncIntervalProvider =
    NotifierProvider<SyncIntervalController, SyncInterval>(
      SyncIntervalController.new,
    );

class SyncIntervalController extends Notifier<SyncInterval> {
  @override
  SyncInterval build() =>
      ref.watch(syncIntervalStoreProvider).read() ?? SyncInterval.fallback;

  Future<void> ensureScheduled() => _apply(ExistingSchedule.keep);

  Future<void> select(SyncInterval interval) async {
    if (interval == state) return;
    state = interval;
    await ref.read(syncIntervalStoreProvider).write(interval);
    await _apply(ExistingSchedule.replace);
  }

  // A launch or a reset must not register a job that has nothing to do: no
  // ring, and no Health Connect read it may run in the background.
  Future<void> _apply(ExistingSchedule existing) async {
    final scheduler = ref.read(syncSchedulerProvider);
    final wanted = await wantsBackgroundSync(
      rings: ref.read(syncStoreProvider),
      reads: ref.read(healthReadStoreProvider),
      reader: ref.read(healthReaderProvider),
    );
    if (!wanted) {
      await scheduler.cancel();
      return;
    }
    await scheduler.schedule(state, existing: existing);
  }
}
