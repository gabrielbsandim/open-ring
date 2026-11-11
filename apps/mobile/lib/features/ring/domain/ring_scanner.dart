import 'package:open_ring/features/ring/domain/discovered_device.dart';

// Failures surface as BleTransportException so the lab treats scan and link
// errors the same way.
abstract interface class RingScanner {
  Stream<List<DiscoveredDevice>> get results;
  Stream<bool> get isScanning;

  Future<void> start(Duration timeout);
  Future<void> stop();
}
