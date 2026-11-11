import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  Future<void> ensureScheduled() =>
      ref.read(syncSchedulerProvider).schedule(state);

  Future<void> select(SyncInterval interval) async {
    if (interval == state) return;
    state = interval;
    await ref.read(syncIntervalStoreProvider).write(interval);
    await ref
        .read(syncSchedulerProvider)
        .schedule(interval, existing: ExistingSchedule.replace);
  }
}
