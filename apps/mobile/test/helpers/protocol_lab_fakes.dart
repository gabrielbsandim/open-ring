import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:open_ring/features/ring/application/protocol_lab_controller.dart';
import 'package:open_ring/features/ring/application/protocol_lab_state.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/features/ring/domain/frame_log_entry.dart';
import 'package:open_ring/features/ring/domain/ring_scanner.dart';
import 'package:open_ring/features/ring/domain/session_log_exporter.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:ring_driver/testing.dart';
import 'package:ring_protocol/ring_protocol.dart';

const v1Write = GattCharacteristic(
  service: ColmiGatt.v1Service,
  characteristic: ColmiGatt.v1Write,
);

const v1Notify = GattCharacteristic(
  service: ColmiGatt.v1Service,
  characteristic: ColmiGatt.v1Notify,
);

const bigDataNotify = GattCharacteristic(
  service: ColmiGatt.bigDataService,
  characteristic: ColmiGatt.bigDataNotify,
);

final labEpoch = DateTime.utc(2026, 11, 10, 12);

const sampleDevices = [
  DiscoveredDevice(id: 'AA:BB:CC:00:00:01', name: 'Kitchen speaker', rssi: -40),
  DiscoveredDevice(id: 'AA:BB:CC:00:00:02', name: 'R09_C0FE', rssi: -71),
  DiscoveredDevice(
    id: 'AA:BB:CC:00:00:03',
    name: '',
    rssi: -55,
    serviceUuids: [ColmiGatt.v1Service],
  ),
];

final List<int> batteryReply = [0x03, 80, 1, ...List.filled(12, 0), 84];

Iterable<GattPacket> batteryResponder(GattPacket write) sync* {
  if (write.bytes.first != V1Command.battery.id) return;
  yield GattPacket(v1Notify, batteryReply);
}

class FakeRingScanner implements RingScanner {
  new({this.found = const [], this.failure});

  final List<DiscoveredDevice> found;
  final BleTransportException? failure;

  final _results = StreamController<List<DiscoveredDevice>>.broadcast();
  final _scanning = StreamController<bool>.broadcast();

  int starts = 0;
  int stops = 0;

  @override
  Stream<List<DiscoveredDevice>> get results => _results.stream;

  @override
  Stream<bool> get isScanning => _scanning.stream;

  @override
  Future<void> start(Duration timeout) async {
    starts++;
    final error = failure;
    if (error != null) throw error;
    _scanning.add(true);
    _results.add(found);
  }

  @override
  Future<void> stop() async {
    stops++;
    _scanning.add(false);
  }
}

class RecordingExporter implements SessionLogExporter {
  new({this.failure});

  final SessionLogExportException? failure;
  final exports = <({String fileName, String contents})>[];

  @override
  Future<void> export({
    required String fileName,
    required String contents,
  }) async {
    final error = failure;
    if (error != null) throw error;
    exports.add((fileName: fileName, contents: contents));
  }
}

class TickingClock {
  new(this._next);

  DateTime _next;

  DateTime call() {
    final now = _next;
    _next = _next.add(const Duration(milliseconds: 250));
    return now;
  }
}

class SeededProtocolLabController extends ProtocolLabController {
  new(this.seed);

  final ProtocolLabState seed;

  @override
  ProtocolLabState build() {
    super.build();
    return seed;
  }
}

ProtocolLabState busyLabState() => ProtocolLabState(
  devices: DiscoveredDevice.rank([
    ...sampleDevices,
    const DiscoveredDevice(
      id: '6F1C3A52-8B1E-4C1F-9D4A-0E2B7C9F1A3D',
      name: 'A device with a rather long advertised name',
      rssi: -88,
    ),
  ]),
  link: TransportState.connected,
  device: sampleDevices[1],
  log: [
    FrameLogEntry(
      at: labEpoch,
      direction: FrameDirection.tx,
      characteristic: ColmiGatt.v1Write,
      bytes: [0x03, ...List.filled(14, 0), 0x03],
    ),
    FrameLogEntry(
      at: labEpoch.add(const Duration(milliseconds: 120)),
      direction: FrameDirection.rx,
      characteristic: ColmiGatt.v1Notify,
      bytes: batteryReply,
    ),
    FrameLogEntry(
      at: labEpoch.add(const Duration(seconds: 1)),
      direction: FrameDirection.rx,
      characteristic: ColmiGatt.bigDataNotify,
      bytes: const [0xBC, 0x27, 0x00, 0x00, 0xFF, 0xFF],
    ),
  ],
  notice: const TransportFailure(
    'connect: ANDROID_SPECIFIC_ERROR (GATT_ERROR 133)',
  ),
);

List<Override> protocolLabOverrides({
  BleTransport? transport,
  RingScanner? scanner,
  SessionLogExporter? exporter,
  DateTime Function()? clock,
  ProtocolLabState? seed,
}) => [
  bleTransportProvider.overrideWithValue(transport ?? FakeBleTransport()),
  ringScannerProvider.overrideWithValue(scanner ?? FakeRingScanner()),
  sessionLogExporterProvider.overrideWithValue(exporter ?? RecordingExporter()),
  labClockProvider.overrideWithValue(clock ?? TickingClock(labEpoch).call),
  if (seed != null)
    protocolLabProvider.overrideWith(() => SeededProtocolLabController(seed)),
];
