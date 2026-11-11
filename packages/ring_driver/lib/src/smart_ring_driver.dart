import 'package:ring_driver/src/ring_types.dart';

abstract interface class SmartRingDriver {
  RingIdentity get identity;
  Set<RingCapability> get capabilities;
  Stream<RingLinkState> get linkState;

  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> syncTime(DateTime now);
  Future<BatteryStatus> readBattery();
  Future<Duration?> readHeartRateInterval();
  Future<void> setHeartRateInterval(Duration interval, {bool enabled = true});
  Future<bool> readMonitor(RingMonitor monitor);
  Future<void> setMonitor(RingMonitor monitor, {required bool enabled});
  Future<void> findDevice();

  Future<List<ActivityBucket>> pullActivity(DateTime since);
  Future<List<HeartRateSample>> pullHeartRate(DateTime since);
  Future<List<Spo2Sample>> pullSpo2(DateTime since);
  Future<List<StressSample>> pullStress(DateTime since);
  Future<List<HrvSample>> pullHrv(DateTime since);
  Future<List<SleepSegment>> pullSleep(DateTime since);

  Stream<LiveReading> startLive(LiveKind kind);
  Future<void> stopLive();

  Stream<LiveReading> startHeartRateStream();
  Future<void> stopHeartRateStream();
}
