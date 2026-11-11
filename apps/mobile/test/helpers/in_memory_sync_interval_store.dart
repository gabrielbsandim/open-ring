import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/domain/sync_interval_store.dart';

class InMemorySyncIntervalStore implements SyncIntervalStore {
  new([this.saved]);

  SyncInterval? saved;
  int writes = 0;

  @override
  SyncInterval? read() => saved;

  @override
  Future<void> write(SyncInterval interval) async {
    saved = interval;
    writes++;
  }
}
