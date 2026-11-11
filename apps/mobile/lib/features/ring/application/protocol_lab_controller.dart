import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/ring/application/protocol_lab_state.dart';
import 'package:open_ring/features/ring/domain/checksum_rule.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/features/ring/domain/frame_insight.dart';
import 'package:open_ring/features/ring/domain/frame_log_entry.dart';
import 'package:open_ring/features/ring/domain/raw_frame.dart';
import 'package:open_ring/features/ring/domain/ring_scanner.dart';
import 'package:open_ring/features/ring/domain/session_log_exporter.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:ring_protocol/ring_protocol.dart';

final bleTransportProvider = Provider<BleTransport>(
  (ref) => throw UnimplementedError('Override bleTransportProvider.'),
);

final ringScannerProvider = Provider<RingScanner>(
  (ref) => throw UnimplementedError('Override ringScannerProvider.'),
);

final sessionLogExporterProvider = Provider<SessionLogExporter>(
  (ref) => throw UnimplementedError('Override sessionLogExporterProvider.'),
);

final labClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final protocolLabProvider =
    NotifierProvider<ProtocolLabController, ProtocolLabState>(
      ProtocolLabController.new,
    );

class ProtocolLabController extends Notifier<ProtocolLabState> {
  static const scanTimeout = Duration(seconds: 15);
  static const findDevicePayload = [0x55, 0xAA];

  static const commandTarget = GattCharacteristic(
    service: ColmiGatt.v1Service,
    characteristic: ColmiGatt.v1Write,
  );

  static const notifySources = [
    GattCharacteristic(
      service: ColmiGatt.v1Service,
      characteristic: ColmiGatt.v1Notify,
    ),
    GattCharacteristic(
      service: ColmiGatt.bigDataService,
      characteristic: ColmiGatt.bigDataNotify,
    ),
  ];

  final _frames = <StreamSubscription<List<int>>>[];

  BleTransport get _transport => ref.read(bleTransportProvider);
  RingScanner get _scanner => ref.read(ringScannerProvider);
  DateTime _now() => ref.read(labClockProvider)();

  @override
  ProtocolLabState build() {
    final scanner = ref.watch(ringScannerProvider);
    final transport = ref.watch(bleTransportProvider);
    final subscriptions = [
      scanner.results.listen(_onDevices),
      scanner.isScanning.listen(_onScanning),
      transport.state.listen(_onLink),
    ];
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
      _stopFrames();
    });
    return const ProtocolLabState();
  }

  Future<void> startScan() async {
    state = state.withNotice(null);
    await _attempt(() => _scanner.start(scanTimeout));
  }

  Future<void> stopScan() => _attempt(_scanner.stop);

  Future<void> connect(DiscoveredDevice device) async {
    state = state.withDevice(device).withNotice(null);
    final connected = await _attempt(() async {
      await _scanner.stop();
      await _transport.connect(device.id);
    });
    if (!connected || !ref.mounted) return;
    _listenForFrames();
  }

  Future<void> disconnect() async {
    _stopFrames();
    await _attempt(_transport.disconnect);
  }

  void selectChecksum(ChecksumRule rule) =>
      state = state.copyWith(checksum: rule);

  Future<void> readBattery() =>
      _send(state.checksum.codec.encode(V1Command.battery));

  Future<void> findDevice() => _send(
    state.checksum.codec.encode(V1Command.findDevice, findDevicePayload),
  );

  Future<void> setTime() =>
      _send(setTimeRequest(_now().toLocal(), codec: state.checksum.codec));

  Future<void> readAutoMonitor(AutoMonitor monitor) =>
      _send(autoMonitorReadRequest(monitor, codec: state.checksum.codec));

  Future<void> readTodayTotals() =>
      _send(todayTotalsRequest(codec: state.checksum.codec));

  Future<void> startStopProbe() async {
    const probe = StopProbe();
    state = state.copyWith(stopProbe: probe);
    await _send(
      realTimeRequest(
        probe.type,
        RealTimeAction.start,
        codec: state.checksum.codec,
      ),
    );
  }

  Future<void> sendRaw(String input) async {
    switch (RawFrame.parse(input)) {
      case InvalidRawFrame(:final error, :final byteCount):
        state = state.withNotice(RawFrameRejected(error, byteCount: byteCount));
      case ValidRawFrame(:final bytes):
        await _send(bytes);
    }
  }

  void clearLog() => state = state.copyWith(log: const []);

  Future<void> exportLog() async {
    if (state.log.isEmpty) return;
    final exporter = ref.read(sessionLogExporterProvider);
    state = state.withNotice(null);
    try {
      await exporter.export(
        fileName: exportFileName(_now()),
        contents: SessionLog.encode(state.log),
      );
    } on SessionLogExportException catch (error) {
      if (!ref.mounted) return;
      state = state.withNotice(ExportFailure(error.message));
    }
  }

  static String exportFileName(DateTime at) {
    final utc = at.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    final date = '${utc.year}${two(utc.month)}${two(utc.day)}';
    final time = '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
    return 'openring-lab-$date-${time}Z.jsonl';
  }

  // The tx entry keeps its place from before the write, so a reply that
  // lands while the write is still awaited is logged after it.
  Future<void> _send(List<int> bytes) async {
    final at = _now();
    final position = state.log.length;
    state = state.withNotice(null);
    final sent = await _attempt(() => _transport.write(commandTarget, bytes));
    if (!sent || !ref.mounted) return;
    final entry = FrameLogEntry(
      at: at,
      direction: FrameDirection.tx,
      characteristic: commandTarget.characteristic,
      bytes: bytes,
    );
    final log = [...state.log]
      ..insert(math.min(position, state.log.length), entry);
    state = state.copyWith(log: log);
  }

  void _listenForFrames() {
    _stopFrames();
    for (final source in notifySources) {
      _frames.add(
        _transport
            .notifications(source)
            .listen((bytes) => _onFrame(source, bytes), onError: _onFrameError),
      );
    }
  }

  void _stopFrames() {
    for (final subscription in _frames) {
      unawaited(subscription.cancel());
    }
    _frames.clear();
  }

  void _onFrame(GattCharacteristic source, List<int> bytes) {
    final entry = FrameLogEntry(
      at: _now(),
      direction: FrameDirection.rx,
      characteristic: source.characteristic,
      bytes: bytes,
    );
    state = state.copyWith(log: [...state.log, entry]);
    _trackProbe(entry);
  }

  // The stop goes out after the first usable reading, so the log shows
  // whether 0x69 frames keep coming once the ring has 0x6A.
  void _trackProbe(FrameLogEntry entry) {
    final probe = state.stopProbe;
    if (probe == null) return;
    final reading = switch (FrameInsight.of(entry)?.reading) {
      RealTimeFrame(:final reading) when reading.type == probe.type => reading,
      _ => null,
    };
    if (reading == null) return;
    final counted = probe.counted();
    state = state.copyWith(stopProbe: counted);
    if (counted.stopSent || reading.isError || reading.value == 0) return;
    state = state.copyWith(stopProbe: counted.stopped());
    unawaited(
      _send(realTimeStopRequest(probe.type, codec: state.checksum.codec)),
    );
  }

  void _onFrameError(Object error) {
    if (error is! BleTransportException) return;
    state = state.withNotice(TransportFailure(error.message));
  }

  void _onDevices(List<DiscoveredDevice> devices) =>
      state = state.copyWith(devices: DiscoveredDevice.rank(devices));

  void _onScanning(bool scanning) => state = state.copyWith(scanning: scanning);

  void _onLink(TransportState link) {
    if (link == TransportState.disconnected) _stopFrames();
    state = state.copyWith(link: link);
  }

  Future<bool> _attempt(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on BleTransportException catch (error) {
      if (!ref.mounted) return false;
      state = state.withNotice(TransportFailure(error.message));
      return false;
    }
  }
}
