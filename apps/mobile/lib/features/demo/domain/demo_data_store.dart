import 'package:open_ring/features/demo/domain/demo_data.dart';

abstract interface class DemoDataStore {
  // Drops whatever an earlier demo left, so a refresh never duplicates rows.
  Future<void> replace(DemoData data);

  Future<void> wipe();
}
