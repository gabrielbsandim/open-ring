import 'package:ring_driver/ring_driver.dart';

abstract interface class PairedRingStore {
  Future<void> save(RingIdentity ring, {required DateTime at});
}

abstract interface class BluetoothRadio {
  // Asks the OS to turn the radio on where it can (Android), then reports
  // whether it is on.
  Future<bool> ensureOn();
}
