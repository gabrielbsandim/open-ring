import 'package:open_ring/features/backup/application/restore_coordinator.dart';
import 'package:open_ring/features/ring/domain/sync_scheduler.dart';
import 'package:open_ring/features/ring/infrastructure/method_channel_sync_service.dart';

final class AndroidBackgroundWork implements BackgroundWork {
  const new({required this._scheduler, required this._syncService});

  final SyncScheduler _scheduler;
  final MethodChannelSyncService _syncService;

  @override
  Future<void> stopAll() async {
    await _scheduler.cancel();
    await _syncService.stop();
  }
}
