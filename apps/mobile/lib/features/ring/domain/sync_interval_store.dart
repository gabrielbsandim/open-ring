import 'package:open_ring/features/ring/domain/sync_interval.dart';

abstract interface class SyncIntervalStore {
  SyncInterval? read();

  Future<void> write(SyncInterval interval);
}
