import 'dart:io';

import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/domain/sync_scheduler.dart';
import 'package:workmanager/workmanager.dart';

const ringSyncTaskId = 'gbs.openring.app.sync';

abstract base class WorkmanagerSyncScheduler implements SyncScheduler {
  new(this.dispatcher, Workmanager? workmanager)
    : workmanager = workmanager ?? Workmanager();

  static SyncScheduler forPlatform(
    void Function() dispatcher, {
    Workmanager? workmanager,
  }) {
    if (Platform.isIOS) return IosSyncScheduler(dispatcher, workmanager);
    return AndroidSyncScheduler(dispatcher, workmanager);
  }

  final void Function() dispatcher;
  final Workmanager workmanager;
  Future<void>? _initialized;

  Future<void> register(SyncInterval interval, ExistingSchedule existing);

  @override
  Future<void> schedule(
    SyncInterval interval, {
    ExistingSchedule existing = ExistingSchedule.keep,
  }) async {
    await (_initialized ??= workmanager.initialize(dispatcher));
    await register(interval, existing);
  }

  @override
  Future<void> cancel() => workmanager.cancelByUniqueName(ringSyncTaskId);
}

final class AndroidSyncScheduler extends WorkmanagerSyncScheduler {
  new(super.dispatcher, [super.workmanager]);

  @override
  Future<void> register(SyncInterval interval, ExistingSchedule existing) =>
      workmanager.registerPeriodicTask(
        ringSyncTaskId,
        ringSyncTaskId,
        frequency: interval.duration,
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: switch (existing) {
          ExistingSchedule.keep => ExistingPeriodicWorkPolicy.keep,
          ExistingSchedule.replace => ExistingPeriodicWorkPolicy.update,
        },
      );
}

// BGTaskScheduler has no keep policy: submitting the same identifier replaces
// the pending request, and iOS treats the delay only as an earliest start.
final class IosSyncScheduler extends WorkmanagerSyncScheduler {
  new(super.dispatcher, [super.workmanager]);

  @override
  Future<void> register(SyncInterval interval, ExistingSchedule existing) =>
      workmanager.registerPeriodicTask(
        ringSyncTaskId,
        ringSyncTaskId,
        initialDelay: interval.duration,
      );
}
