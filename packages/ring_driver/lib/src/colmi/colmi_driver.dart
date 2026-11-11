import 'dart:async';

import 'package:ring_driver/src/ble_transport.dart';
import 'package:ring_driver/src/ring_types.dart';
import 'package:ring_driver/src/smart_ring_driver.dart';
import 'package:ring_protocol/ring_protocol.dart';

final class ColmiProtocolException implements Exception {
  const new(this.error);

  final ParseError error;

  @override
  String toString() => 'ColmiProtocolException: $error';
}

typedef _Step<T> = ParseResult<T>? Function(List<int> bytes);

typedef _Day = ({int daysAgo, DateTime midnight});

final class ColmiDriver implements SmartRingDriver {
  new({
    required BleTransport transport,
    this._name = 'COLMI R09',
    this._model = 'R09',
    this._codec = const V1FrameCodec(),
    this._clock = DateTime.now,
    Duration responseTimeout = const Duration(seconds: 10),
    this._historyDays = 7,
    this._verifyBigDataCrc = true,
    this._keepAliveEvery = defaultKeepAliveEvery,
  }) : _transport = transport,
       _timeout = responseTimeout {
    _stateSub = transport.state.listen(_onTransportState);
  }

  static const defaultKeepAliveEvery = Duration(seconds: 20);

  static const write = GattCharacteristic(
    service: ColmiGatt.v1Service,
    characteristic: ColmiGatt.v1Write,
  );
  static const notify = GattCharacteristic(
    service: ColmiGatt.v1Service,
    characteristic: ColmiGatt.v1Notify,
  );
  static const bigDataWrite = GattCharacteristic(
    service: ColmiGatt.bigDataService,
    characteristic: ColmiGatt.bigDataWrite,
  );
  static const bigDataNotify = GattCharacteristic(
    service: ColmiGatt.bigDataService,
    characteristic: ColmiGatt.bigDataNotify,
  );

  final BleTransport _transport;
  final String _name;
  final String _model;
  final V1FrameCodec _codec;
  final DateTime Function() _clock;
  final Duration _timeout;
  final int _historyDays;
  final bool _verifyBigDataCrc;
  final Duration _keepAliveEvery;

  final _link = StreamController<RingLinkState>.broadcast();
  final _v1 = StreamController<List<int>>.broadcast();
  final _bigData = StreamController<List<int>>.broadcast();

  late final StreamSubscription<TransportState> _stateSub;
  StreamSubscription<List<int>>? _v1Sub;
  StreamSubscription<List<int>>? _bigDataSub;
  String? _deviceId;
  RealTimeType? _liveType;
  bool _heartRateStreaming = false;
  Timer? _keepAlive;
  DeviceCapabilities? _capabilities;

  DeviceCapabilities? get reportedCapabilities => _capabilities;

  Stream<List<int>> get v1Notifications => _v1.stream;

  @override
  RingIdentity get identity =>
      RingIdentity(deviceId: _deviceId ?? '', name: _name, model: _model);

  @override
  Set<RingCapability> get capabilities => const {
    RingCapability.battery,
    RingCapability.activity,
    RingCapability.heartRateLog,
    RingCapability.spo2,
    RingCapability.stress,
    RingCapability.hrv,
    RingCapability.sleep,
    RingCapability.liveHeartRate,
    RingCapability.liveSpo2,
    RingCapability.heartRateInterval,
    RingCapability.autoMonitors,
    RingCapability.findDevice,
  };

  @override
  Stream<RingLinkState> get linkState => _link.stream;

  @override
  Future<void> connect(String deviceId) async {
    await _transport.connect(deviceId);
    _deviceId = deviceId;
    await _cancelNotifications();
    _v1Sub = _transport.notifications(notify).listen(_v1.add);
    _bigDataSub = _transport.notifications(bigDataNotify).listen(_bigData.add);
  }

  @override
  Future<void> disconnect() async {
    _link.add(RingLinkState.disconnecting);
    _liveType = null;
    _endHeartRateStream();
    await _cancelNotifications();
    await _transport.disconnect();
  }

  Future<void> close() async {
    _endHeartRateStream();
    await _cancelNotifications();
    await _stateSub.cancel();
    await _link.close();
    await _v1.close();
    await _bigData.close();
  }

  @override
  Future<void> syncTime(DateTime now) async {
    _capabilities = await _v1Exchange(
      setTimeRequest(now, codec: _codec),
      V1Command.setDateTime.id,
      parseSetTime,
    );
  }

  @override
  Future<Duration?> readHeartRateInterval() async {
    final setting = await _v1Exchange(
      autoHeartRateReadRequest(codec: _codec),
      V1Command.autoHeartRateSetting.id,
      parseAutoHeartRateSetting,
    );
    if (!setting.enabled) return null;
    return Duration(minutes: setting.intervalMinutes);
  }

  @override
  Future<void> setHeartRateInterval(Duration interval, {bool enabled = true}) =>
      _v1Exchange(
        autoHeartRateWriteRequest(
          AutoHeartRateSetting(
            enabled: enabled,
            intervalMinutes: interval.inMinutes,
          ),
          codec: _codec,
        ),
        V1Command.autoHeartRateSetting.id,
        (frame) => parseSettingAck(frame, V1Command.autoHeartRateSetting),
      );

  @override
  Future<bool> readMonitor(RingMonitor monitor) {
    final auto = _autoMonitor(monitor);
    return _v1Exchange(
      autoMonitorReadRequest(auto, codec: _codec),
      auto.command.id,
      (frame) => parseAutoMonitor(frame, auto),
    );
  }

  @override
  Future<void> setMonitor(RingMonitor monitor, {required bool enabled}) {
    final auto = _autoMonitor(monitor);
    return _v1Exchange(
      autoMonitorWriteRequest(auto, enabled: enabled, codec: _codec),
      auto.command.id,
      (frame) => parseSettingAck(frame, auto.command),
    );
  }

  static AutoMonitor _autoMonitor(RingMonitor monitor) => switch (monitor) {
    RingMonitor.spo2 => AutoMonitor.spo2,
    RingMonitor.stress => AutoMonitor.stress,
    RingMonitor.hrv => AutoMonitor.hrv,
  };

  @override
  Future<BatteryStatus> readBattery() async {
    final reading = await _v1Exchange(
      _codec.encode(V1Command.battery),
      V1Command.battery.id,
      parseBattery,
    );
    return BatteryStatus(percent: reading.percent, charging: reading.charging);
  }

  @override
  Future<List<ActivityBucket>> pullActivity(DateTime since) async {
    final buckets = <ActivityBucket>[];
    for (final day in _days(since)) {
      final assembler = ActivityLogAssembler();
      final records = await _v1Exchange(
        activityLogRequest(daysAgo: day.daysAgo, codec: _codec),
        V1Command.activityLog.id,
        assembler.add,
      );
      buckets.addAll(records.map(_bucket));
    }
    return [
      for (final bucket in buckets)
        if (!bucket.start.isBefore(since)) bucket,
    ];
  }

  @override
  Future<List<HeartRateSample>> pullHeartRate(DateTime since) async {
    final samples = <HeartRateSample>[];
    for (final day in _days(since)) {
      final log = await _v1Exchange(
        heartRateLogRequest(_wallClockSeconds(day.midnight), codec: _codec),
        V1Command.heartRateLog.id,
        SlotLogAssembler.heartRate().add,
      );
      for (final (at, value) in _slots(day.midnight, log, since)) {
        samples.add(HeartRateSample(at: at, bpm: value));
      }
    }
    return samples;
  }

  @override
  Future<List<StressSample>> pullStress(DateTime since) async {
    final today = _days(since).first;
    final log = await _v1Exchange(
      stressLogRequest(codec: _codec),
      V1Command.stressLog.id,
      SlotLogAssembler.stress().add,
    );
    return [
      for (final (at, value) in _slots(today.midnight, log, since))
        StressSample(at: at, level: value),
    ];
  }

  @override
  Future<List<HrvSample>> pullHrv(DateTime since) async {
    final samples = <HrvSample>[];
    for (final day in _days(since)) {
      final log = await _v1Exchange(
        hrvLogRequest(daysAgo: day.daysAgo, codec: _codec),
        V1Command.hrvLog.id,
        SlotLogAssembler.hrv().add,
      );
      for (final (at, value) in _slots(day.midnight, log, since)) {
        samples.add(HrvSample(at: at, milliseconds: value));
      }
    }
    return samples;
  }

  @override
  Future<List<Spo2Sample>> pullSpo2(DateTime since) async {
    final days = await _bigDataExchange(BigDataId.spo2, parseSpo2);
    final today = _today();
    final samples = <Spo2Sample>[];
    for (final day in days) {
      for (var hour = 0; hour < day.hourly.length; hour++) {
        final range = day.hourly[hour];
        final at = DateTime(
          today.year,
          today.month,
          today.day - day.daysAgo,
          hour,
        );
        if (!range.hasData || at.isBefore(since)) continue;
        samples.add(
          Spo2Sample(at: at, percent: ((range.min + range.max) / 2).round()),
        );
      }
    }
    return samples;
  }

  @override
  Future<List<SleepSegment>> pullSleep(DateTime since) async {
    final days = await _bigDataExchange(BigDataId.sleep, parseSleep);
    final today = _today();
    return [
      for (final day in days)
        for (final segment in _segments(today, day))
          if (!segment.start.isBefore(since)) segment,
    ];
  }

  @override
  Stream<LiveReading> startLive(LiveKind kind) {
    final type = switch (kind) {
      LiveKind.heartRate => RealTimeType.heartRate,
      LiveKind.spo2 => RealTimeType.spo2,
    };
    _liveType = type;
    StreamSubscription<List<int>>? source;
    late final StreamController<LiveReading> controller;
    controller = StreamController<LiveReading>(
      onListen: () {
        source = _v1.stream.listen((bytes) {
          final reading = _liveReading(bytes, type, kind);
          if (reading != null) controller.add(reading);
        });
        unawaited(
          _sendLive(
            realTimeRequest(type, RealTimeAction.start, codec: _codec),
            controller,
          ),
        );
      },
      onCancel: () => source?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<void> stopLive() async {
    final type = _liveType;
    if (type == null) return;
    _liveType = null;
    await _transport.write(write, realTimeStopRequest(type, codec: _codec));
  }

  @override
  Stream<LiveReading> startHeartRateStream() {
    _heartRateStreaming = true;
    StreamSubscription<List<int>>? source;
    Timer? keepAlive;
    DateTime? last;
    late final StreamController<LiveReading> controller;
    controller = StreamController<LiveReading>(
      onListen: () {
        source = _v1.stream.listen((bytes) {
          final reading = _streamedHeartRate(bytes, last);
          if (reading == null) return;
          last = reading.at;
          controller.add(reading);
        });
        _keepAlive?.cancel();
        keepAlive = Timer.periodic(
          _keepAliveEvery,
          (_) => unawaited(
            _sendLive(
              _heartRateStreamRequest(ContinuousHeartRateAction.keepAlive),
              controller,
            ),
          ),
        );
        _keepAlive = keepAlive;
        unawaited(
          _sendLive(
            _heartRateStreamRequest(ContinuousHeartRateAction.enable),
            controller,
          ),
        );
      },
      onCancel: () {
        keepAlive?.cancel();
        if (identical(_keepAlive, keepAlive)) _keepAlive = null;
        return source?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> stopHeartRateStream() async {
    if (!_heartRateStreaming) return;
    _endHeartRateStream();
    await _transport.write(
      write,
      _heartRateStreamRequest(ContinuousHeartRateAction.disable),
    );
  }

  @override
  Future<void> findDevice() => _v1Exchange(
    findDeviceRequest(codec: _codec),
    V1Command.findDevice.id,
    parseFindDevice,
  );

  Future<void> _sendLive(
    List<int> request,
    StreamController<LiveReading> controller,
  ) async {
    try {
      await _transport.write(write, request);
    } on Object catch (error, stackTrace) {
      controller.addError(error, stackTrace);
    }
  }

  LiveReading? _liveReading(List<int> bytes, RealTimeType type, LiveKind kind) {
    if (bytes.isEmpty || bytes.first != V1Command.realTimeData.id) return null;
    final result = _codec.parse(bytes, parseRealTimeReading);
    if (result is! Parsed<RealTimeReading>) return null;
    final reading = result.value;
    if (reading.type != type || reading.isError || reading.value == 0) {
      return null;
    }
    return LiveReading(kind: kind, value: reading.value, at: _clock());
  }

  List<int> _heartRateStreamRequest(ContinuousHeartRateAction action) =>
      continuousHeartRateRequest(action, codec: _codec);

  void _endHeartRateStream() {
    _heartRateStreaming = false;
    _keepAlive?.cancel();
    _keepAlive = null;
  }

  // The ring can repeat a reply inside one second; Gadgetbridge keeps the
  // first one per wall clock second (realtimeHeartRate).
  LiveReading? _streamedHeartRate(List<int> bytes, DateTime? last) {
    if (bytes.isEmpty || bytes.first != V1Command.continuousHeartRate.id) {
      return null;
    }
    final result = _codec.parse(bytes, parseContinuousHeartRate);
    if (result is! Parsed<int> || result.value == 0) return null;
    final at = _clock();
    if (last != null && _epochSecond(at) <= _epochSecond(last)) return null;
    return LiveReading(kind: LiveKind.heartRate, value: result.value, at: at);
  }

  static int _epochSecond(DateTime at) =>
      at.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;

  Future<T> _v1Exchange<T>(
    List<int> request,
    int command,
    ParseResult<T>? Function(V1Frame frame) step,
  ) => _exchange(write, request, _v1.stream, (bytes) {
    if (bytes.isEmpty) return null;
    if (bytes.first & ~V1Frame.errorBit != command) return null;
    return switch (_codec.decode(bytes)) {
      Parsed(:final value) => step(value),
      ParseFailure(:final error) => ParseFailure(error),
    };
  });

  Future<T> _bigDataExchange<T>(
    int dataId,
    ParseResult<T> Function(BigDataPacket packet) parse,
  ) {
    final assembler = BigDataAssembler(verifyCrc: _verifyBigDataCrc);
    return _exchange(
      bigDataWrite,
      bigDataRequest(dataId),
      _bigData.stream,
      (bytes) => switch (assembler.add(bytes)) {
        null => null,
        Parsed(:final value) when value.dataId != dataId => null,
        Parsed(:final value) => parse(value),
        ParseFailure(:final error) => ParseFailure(error),
      },
    );
  }

  Future<T> _exchange<T>(
    GattCharacteristic target,
    List<int> request,
    Stream<List<int>> source,
    _Step<T> step,
  ) async {
    final completer = Completer<T>();
    final subscription = source.listen((bytes) {
      if (completer.isCompleted) return;
      switch (step(bytes)) {
        case null:
          return;
        case Parsed(:final value):
          completer.complete(value);
        case ParseFailure(:final error):
          completer.completeError(ColmiProtocolException(error));
      }
    });
    try {
      await _transport.write(target, request);
      return await completer.future.timeout(_timeout);
    } finally {
      await subscription.cancel();
    }
  }

  DateTime _today() {
    final now = _clock();
    return DateTime(now.year, now.month, now.day);
  }

  List<_Day> _days(DateTime since) {
    final today = _today();
    final local = since.toLocal();
    final span = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(local.year, local.month, local.day)).inDays;
    final last = span.clamp(0, _historyDays - 1);
    return [
      for (var i = 0; i <= last; i++)
        (
          daysAgo: i,
          midnight: DateTime(today.year, today.month, today.day - i),
        ),
    ];
  }

  // The ring keeps local wall clock time, so a local midnight is sent as if
  // it were UTC (Gadgetbridge fetchHistoryHR, Puxtril HeartRateRequest).
  static int _wallClockSeconds(DateTime midnight) =>
      DateTime.utc(
        midnight.year,
        midnight.month,
        midnight.day,
      ).millisecondsSinceEpoch ~/
      1000;

  Iterable<(DateTime, int)> _slots(
    DateTime midnight,
    SlotLog log,
    DateTime since,
  ) sync* {
    final now = _clock();
    for (var i = 0; i < log.values.length; i++) {
      final minute = i * log.intervalMinutes;
      final value = log.values[i];
      if (value == 0 || minute >= Duration.minutesPerDay) continue;
      final at = DateTime(
        midnight.year,
        midnight.month,
        midnight.day,
        0,
        minute,
      );
      // The ring does not clear future slots of today (Gadgetbridge, tahnok).
      if (at.isAfter(now) || at.isBefore(since)) continue;
      yield (at, value);
    }
  }

  static ActivityBucket _bucket(ActivityRecord record) => ActivityBucket(
    start: DateTime(
      record.year,
      record.month,
      record.day,
      0,
      record.minuteOfDay,
    ),
    duration: const Duration(minutes: 15),
    steps: record.steps,
    distanceMeters: record.distanceMeters,
    activeKilocalories: record.calories / 1000,
  );

  static Iterable<SleepSegment> _segments(DateTime today, SleepDay day) sync* {
    final wake = DateTime(today.year, today.month, today.day - day.daysAgo);
    final startMinute = day.startMinute > day.endMinute
        ? day.startMinute - Duration.minutesPerDay
        : day.startMinute;
    var cursor = DateTime(wake.year, wake.month, wake.day, 0, startMinute);
    for (final period in day.periods) {
      final end = cursor.add(Duration(minutes: period.minutes));
      final stage = _stage(period.stage);
      if (stage != null && period.minutes > 0) {
        yield SleepSegment(start: cursor, end: end, stage: stage);
      }
      cursor = end;
    }
  }

  static SleepStage? _stage(int code) => switch (code) {
    SleepStageCode.light => SleepStage.light,
    SleepStageCode.deep => SleepStage.deep,
    SleepStageCode.rem => SleepStage.rem,
    SleepStageCode.awake => SleepStage.awake,
    _ => null,
  };

  void _onTransportState(TransportState state) {
    _link.add(switch (state) {
      TransportState.disconnected => RingLinkState.disconnected,
      TransportState.connecting => RingLinkState.connecting,
      TransportState.connected => RingLinkState.connected,
    });
  }

  Future<void> _cancelNotifications() async {
    await _v1Sub?.cancel();
    await _bigDataSub?.cancel();
    _v1Sub = null;
    _bigDataSub = null;
  }
}
