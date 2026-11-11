import 'package:open_ring/features/ring/domain/sync_interval.dart';

enum ExistingSchedule { keep, replace }

abstract interface class SyncScheduler {
  Future<void> schedule(
    SyncInterval interval, {
    ExistingSchedule existing = ExistingSchedule.keep,
  });

  Future<void> cancel();
}
