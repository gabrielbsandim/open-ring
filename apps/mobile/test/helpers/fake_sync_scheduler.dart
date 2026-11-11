import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/domain/sync_scheduler.dart';

typedef ScheduleCall = ({SyncInterval interval, ExistingSchedule existing});

class FakeSyncScheduler implements SyncScheduler {
  final calls = <ScheduleCall>[];
  int cancels = 0;

  @override
  Future<void> schedule(
    SyncInterval interval, {
    ExistingSchedule existing = ExistingSchedule.keep,
  }) async {
    calls.add((interval: interval, existing: existing));
  }

  @override
  Future<void> cancel() async => cancels++;
}
