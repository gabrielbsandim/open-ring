import 'dart:async';

import 'package:ring_driver/ring_driver.dart';

class FakeRingDriver implements SmartRingDriver {
  new({
    Set<RingCapability>? capabilities,
    this.battery = const BatteryStatus(percent: 80, charging: false),
  }) : capabilities = capabilities ?? RingCapability.values.toSet();

  @override
  Set<RingCapability> capabilities;

  BatteryStatus battery;
  Object? connectError;
  Completer<void>? connectGate;
  Object? syncTimeError;
  Duration? heartRateInterval = const Duration(minutes: 30);
  Object? disconnectError;
  Object? findError;
  final Map<RingMonitor, bool> monitors = {
    for (final monitor in RingMonitor.values) monitor: true,
  };

  List<ActivityBucket> activity = [];
  List<HeartRateSample> heartRate = [];
  List<Spo2Sample> spo2 = [];
  List<StressSample> stress = [];
  List<HrvSample> hrv = [];
  List<SleepSegment> sleep = [];

  final _live = <StreamController<LiveReading>>[];
  LiveKind? liveKind;
  Object? liveError;

  final failing = <RingCapability, Object>{};
  final sinces = <RingCapability, List<DateTime>>{};
  final calls = <String>[];

  String? _deviceId;

  int get connects => calls.where((c) => c == 'connect').length;

  int get disconnects => calls.where((c) => c == 'disconnect').length;

  @override
  RingIdentity get identity =>
      RingIdentity(deviceId: _deviceId ?? '', name: 'COLMI R09', model: 'R09');

  @override
  Stream<RingLinkState> get linkState => const Stream.empty();

  @override
  Future<void> connect(String deviceId) async {
    calls.add('connect');
    await Future<void>.delayed(Duration.zero);
    await connectGate?.future;
    if (connectError case final error?) _raise(error);
    _deviceId = deviceId;
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    if (disconnectError case final error?) _raise(error);
  }

  @override
  Future<void> syncTime(DateTime now) async {
    calls.add('syncTime');
    if (syncTimeError case final error?) _raise(error);
  }

  @override
  Future<Duration?> readHeartRateInterval() async {
    calls.add('readHeartRateInterval');
    if (failing[RingCapability.heartRateInterval] case final error?) {
      _raise(error);
    }
    return heartRateInterval;
  }

  @override
  Future<void> setHeartRateInterval(
    Duration interval, {
    bool enabled = true,
  }) async {
    calls.add('setHeartRateInterval');
    heartRateInterval = enabled ? interval : null;
  }

  @override
  Future<bool> readMonitor(RingMonitor monitor) async {
    calls.add('readMonitor');
    if (failing[RingCapability.autoMonitors] case final error?) _raise(error);
    return monitors[monitor]!;
  }

  @override
  Future<void> setMonitor(RingMonitor monitor, {required bool enabled}) async {
    calls.add('setMonitor');
    monitors[monitor] = enabled;
  }

  @override
  Future<void> findDevice() async {
    calls.add('findDevice');
    if (findError case final error?) _raise(error);
  }

  @override
  Future<BatteryStatus> readBattery() async {
    calls.add('battery');
    if (failing[RingCapability.battery] case final error?) _raise(error);
    return battery;
  }

  @override
  Future<List<ActivityBucket>> pullActivity(DateTime since) =>
      _pull(RingCapability.activity, since, activity, (b) => b.start);

  @override
  Future<List<HeartRateSample>> pullHeartRate(DateTime since) =>
      _pull(RingCapability.heartRateLog, since, heartRate, (s) => s.at);

  @override
  Future<List<Spo2Sample>> pullSpo2(DateTime since) =>
      _pull(RingCapability.spo2, since, spo2, (s) => s.at);

  @override
  Future<List<StressSample>> pullStress(DateTime since) =>
      _pull(RingCapability.stress, since, stress, (s) => s.at);

  @override
  Future<List<HrvSample>> pullHrv(DateTime since) =>
      _pull(RingCapability.hrv, since, hrv, (s) => s.at);

  @override
  Future<List<SleepSegment>> pullSleep(DateTime since) =>
      _pull(RingCapability.sleep, since, sleep, (s) => s.start);

  @override
  Stream<LiveReading> startLive(LiveKind kind) {
    calls.add('startLive');
    liveKind = kind;
    return _openLive();
  }

  @override
  Stream<LiveReading> startHeartRateStream() {
    calls.add('startHeartRateStream');
    return _openLive();
  }

  Stream<LiveReading> _openLive() {
    if (liveError case final error?) return Stream.error(error);
    // A broadcast cancel completes in the root zone and hangs fake async.
    late final StreamController<LiveReading> controller;
    controller = StreamController<LiveReading>(
      onCancel: () async => _live.remove(controller),
    );
    _live.add(controller);
    return controller.stream;
  }

  void emitLive(LiveReading reading) {
    for (final controller in [..._live]) {
      controller.add(reading);
    }
  }

  @override
  Future<void> stopLive() async {
    calls.add('stopLive');
  }

  @override
  Future<void> stopHeartRateStream() async {
    calls.add('stopHeartRateStream');
  }

  Future<List<T>> _pull<T>(
    RingCapability capability,
    DateTime since,
    List<T> data,
    DateTime Function(T item) at,
  ) async {
    calls.add(capability.name);
    sinces.putIfAbsent(capability, () => []).add(since);
    if (failing[capability] case final error?) _raise(error);
    return [
      for (final item in data)
        if (!at(item).isBefore(since)) item,
    ];
  }

  static Never _raise(Object error) =>
      Error.throwWithStackTrace(error, StackTrace.current);
}
