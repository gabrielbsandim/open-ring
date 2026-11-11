import 'package:ring_driver/ring_driver.dart';

abstract interface class SpotReadingStore {
  Future<void> save(String deviceId, LiveReading reading);
}
