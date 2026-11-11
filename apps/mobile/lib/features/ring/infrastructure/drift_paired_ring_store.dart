import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/ring/domain/ring_pairing.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:ring_driver/ring_driver.dart';

final class DriftPairedRingStore implements PairedRingStore {
  new(AppDatabase db) : _devices = RingDevicesDao(db);

  final RingDevicesDao _devices;

  @override
  Future<void> save(RingIdentity ring, {required DateTime at}) =>
      _devices.pair(ring, at: at);
}
