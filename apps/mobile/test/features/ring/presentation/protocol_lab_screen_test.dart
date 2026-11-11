import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/domain/checksum_rule.dart';
import 'package:open_ring/features/ring/domain/frame_log_entry.dart';
import 'package:open_ring/features/ring/presentation/lab_device_tile.dart';
import 'package:open_ring/features/ring/presentation/protocol_lab_screen.dart';
import 'package:ring_driver/testing.dart';
import 'package:ring_protocol/ring_protocol.dart';

import '../../../helpers/colmi_frames.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/protocol_lab_fakes.dart';

Future<void> pumpLab(
  WidgetTester tester, {
  FakeBleTransport? transport,
  FakeRingScanner? scanner,
  RecordingExporter? exporter,
  Locale locale = const Locale('en'),
}) => pumpScaled(
  tester,
  screenHost(const ProtocolLabScreen()),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: locale,
  size: const Size(400, 4000),
  overrides: protocolLabOverrides(
    transport: transport ?? FakeBleTransport(responder: batteryResponder),
    scanner: scanner ?? FakeRingScanner(found: sampleDevices),
    exporter: exporter,
  ),
);

Future<void> tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> scanAndConnect(WidgetTester tester) async {
  await tapKey(tester, ProtocolLabScreen.scanKey);
  final tile = find.byKey(LabDeviceTile.keyFor(sampleDevices[1].id));
  await tester.ensureVisible(tile);
  await tester.tap(find.descendant(of: tile, matching: find.text('Connect')));
  await tester.pumpAndSettle();
}

bool enabled(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key)).enabled;

Iterable<GattPacket> verificationResponder(GattPacket write) sync* {
  switch (write.bytes.first) {
    case 0x01:
      yield v1(hex('01 00 01 00 22 00 00 00 00 01 00 30 01 00 10 66'));
    case 0x2C:
      yield v1([0x2C, 0x01, 0x01]);
    case 0x36:
      yield v1([0x36, 0x01, 0x00]);
    case 0x38:
      yield v1([0x38, 0x01, 0x01]);
    case 0x48:
      yield v1([
        0x48,
        0,
        0x1F,
        0x40,
        0,
        0x01,
        0xF4,
        0,
        0x30,
        0x39,
        0,
        0x13,
        0x88,
      ]);
    case 0x69:
      yield v1([0x69, 0x01, 0x00, 72]);
    case 0x6A:
      yield v1([0x6A, 0x01]);
  }
}

Future<FakeBleTransport> connectedLab(WidgetTester tester) async {
  final transport = FakeBleTransport(responder: verificationResponder);
  await pumpLab(tester, transport: transport);
  await scanAndConnect(tester);
  return transport;
}

void main() {
  testWidgets('starts disconnected with commands disabled', (tester) async {
    await pumpLab(tester);

    expect(find.text('Not connected'), findsOneWidget);
    expect(find.textContaining('No devices found yet'), findsOneWidget);
    expect(find.textContaining('Frames sent and received'), findsOneWidget);
    for (final key in [
      ProtocolLabScreen.batteryKey,
      ProtocolLabScreen.findDeviceKey,
      ProtocolLabScreen.setTimeKey,
      for (final monitor in AutoMonitor.values)
        ProtocolLabScreen.autoMonitorKey(monitor),
      ProtocolLabScreen.todayTotalsKey,
      ProtocolLabScreen.stopProbeKey,
      ProtocolLabScreen.sendRawKey,
      ProtocolLabScreen.exportKey,
      ProtocolLabScreen.clearKey,
    ]) {
      expect(enabled(tester, key), isFalse, reason: '$key');
    }
  });

  testWidgets('offers no power off or factory reset button', (tester) async {
    await pumpLab(tester);

    final labels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data);
    expect(labels, [
      'Scan',
      'Read battery',
      'Find device',
      'Set time',
      'Read auto SpO2',
      'Read auto stress',
      'Read auto HRV',
      "Read today's totals",
      'Heart rate, then stop',
      'Send raw frame',
      'Export JSON lines',
      'Clear log',
    ]);
  });

  testWidgets('scan lists the Colmi looking device first', (tester) async {
    await pumpLab(tester);

    await tapKey(tester, ProtocolLabScreen.scanKey);

    final tiles = tester.widgetList<LabDeviceTile>(find.byType(LabDeviceTile));
    expect(tiles.map((t) => t.device.id), [
      'AA:BB:CC:00:00:03',
      'AA:BB:CC:00:00:02',
      'AA:BB:CC:00:00:01',
    ]);
    expect(find.text('Looks like a Colmi ring'), findsNWidgets(2));
    expect(find.text('Unnamed device'), findsOneWidget);
    expect(find.text('Signal -71 dBm'), findsOneWidget);
    expect(find.byKey(ProtocolLabScreen.stopScanKey), findsOneWidget);
  });

  testWidgets('connect then read battery shows both frames decoded', (
    tester,
  ) async {
    final transport = FakeBleTransport(responder: batteryResponder);
    await pumpLab(tester, transport: transport);
    await scanAndConnect(tester);

    expect(find.text('Connected to R09_C0FE'), findsOneWidget);
    expect(enabled(tester, ProtocolLabScreen.batteryKey), isTrue);

    await tapKey(tester, ProtocolLabScreen.batteryKey);

    expect(transport.writes.single.bytes.first, 0x03);
    expect(find.text('2 frames'), findsOneWidget);
    expect(find.text('TX'), findsOneWidget);
    expect(find.text('RX'), findsOneWidget);
    expect(
      find.text('03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 03'),
      findsOneWidget,
    );
    expect(
      find.text('03 50 01 00 00 00 00 00 00 00 00 00 00 00 00 54'),
      findsOneWidget,
    );
    expect(find.text('Battery 80%, charging'), findsOneWidget);
    expect(
      find.text('Checksum matches: Sum of bytes & 0xFF / Sum of bytes % 255'),
      findsNWidgets(2),
    );
  });

  testWidgets('find device follows the selected checksum', (tester) async {
    final transport = FakeBleTransport();
    await pumpLab(tester, transport: transport);
    await scanAndConnect(tester);

    await tapKey(tester, ProtocolLabScreen.checksumKey(ChecksumRule.modulo255));
    await tapKey(tester, ProtocolLabScreen.findDeviceKey);

    final frame = transport.writes.single.bytes;
    expect(frame.sublist(0, 3), [0x50, 0x55, 0xAA]);
    expect(frame.last, 0x50);
    expect(find.text('Checksum matches: Sum of bytes % 255'), findsOneWidget);
  });

  testWidgets('a blocked raw frame shows a notice and sends nothing', (
    tester,
  ) async {
    final transport = FakeBleTransport();
    await pumpLab(tester, transport: transport);
    await scanAndConnect(tester);

    await tester.enterText(
      find.byKey(ProtocolLabScreen.rawFieldKey),
      'ff${'00' * 15}',
    );
    await tapKey(tester, ProtocolLabScreen.sendRawKey);

    expect(transport.writes, isEmpty);
    expect(find.byKey(ProtocolLabScreen.noticeKey), findsOneWidget);
    expect(
      find.text('Power off and factory reset are blocked in the lab.'),
      findsOneWidget,
    );
  });

  testWidgets('a raw frame of the wrong length says how long it was', (
    tester,
  ) async {
    await pumpLab(tester);
    await scanAndConnect(tester);

    await tester.enterText(find.byKey(ProtocolLabScreen.rawFieldKey), '03 00');
    await tapKey(tester, ProtocolLabScreen.sendRawKey);

    expect(find.text('A frame has 16 bytes, this one has 2.'), findsOneWidget);
  });

  testWidgets('a valid raw frame is sent and logged', (tester) async {
    final transport = FakeBleTransport();
    await pumpLab(tester, transport: transport);
    await scanAndConnect(tester);

    await tester.enterText(
      find.byKey(ProtocolLabScreen.rawFieldKey),
      '48000000000000000000000000000048',
    );
    await tapKey(tester, ProtocolLabScreen.sendRawKey);

    expect(transport.writes.single.bytes.first, 0x48);
    expect(find.text('1 frame'), findsOneWidget);
  });

  testWidgets('export shares the session as JSON lines', (tester) async {
    final exporter = RecordingExporter();
    await pumpLab(tester, exporter: exporter);
    await scanAndConnect(tester);
    await tapKey(tester, ProtocolLabScreen.batteryKey);

    await tapKey(tester, ProtocolLabScreen.exportKey);

    final lines = SessionLog.decode(exporter.exports.single.contents);
    expect(lines.map((e) => e.direction), [
      FrameDirection.tx,
      FrameDirection.rx,
    ]);
  });

  testWidgets('clear empties the log', (tester) async {
    await pumpLab(tester);
    await scanAndConnect(tester);
    await tapKey(tester, ProtocolLabScreen.batteryKey);

    await tapKey(tester, ProtocolLabScreen.clearKey);

    expect(find.text('TX'), findsNothing);
    expect(find.textContaining('Frames sent and received'), findsOneWidget);
  });

  testWidgets('a connection failure reads as a Bluetooth error', (
    tester,
  ) async {
    await pumpLab(tester, transport: FakeBleTransport(unreachable: true));
    await scanAndConnect(tester);

    expect(
      find.text('Bluetooth error: AA:BB:CC:00:00:02 is unreachable'),
      findsOneWidget,
    );
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('set time shows the capability flags of the reply', (
    tester,
  ) async {
    final transport = await connectedLab(tester);

    await tapKey(tester, ProtocolLabScreen.setTimeKey);

    expect(transport.writes.single.bytes.first, 0x01);
    expect(
      find.text(
        'Supports: blood oxygen, new sleep protocol, manual heart rate, stress',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Does not support: temperature, blood pressure, blood sugar, HRV',
      ),
      findsOneWidget,
    );
  });

  testWidgets('each auto monitor read shows the enabled byte', (tester) async {
    final transport = await connectedLab(tester);

    for (final monitor in AutoMonitor.values) {
      await tapKey(tester, ProtocolLabScreen.autoMonitorKey(monitor));
    }

    expect(transport.writes.map((w) => w.bytes.sublist(0, 2)), [
      [0x2C, 0x01],
      [0x36, 0x01],
      [0x38, 0x01],
    ]);
    expect(find.text('Reply: auto SpO2 on (byte 2 = 0x01)'), findsOneWidget);
    expect(find.text('Reply: auto stress off (byte 2 = 0x00)'), findsOneWidget);
    expect(find.text('Reply: auto HRV on (byte 2 = 0x01)'), findsOneWidget);
  });

  testWidgets("today's totals shows both byte orders", (tester) async {
    final transport = await connectedLab(tester);

    await tapKey(tester, ProtocolLabScreen.todayTotalsKey);

    expect(transport.writes.single.bytes.first, 0x48);
    expect(
      find.text(
        'Big endian: 8000 steps, 500 running, 12345 cal, 5000 m, 0 min active',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Little endian: 4202240 steps, 15991040 running, 3747840 cal, '
        '8917760 m, 0 min active',
      ),
      findsOneWidget,
    );
  });

  testWidgets('heart rate then stop counts readings before and after 0x6A', (
    tester,
  ) async {
    final transport = await connectedLab(tester);

    await tapKey(tester, ProtocolLabScreen.stopProbeKey);

    expect(transport.writes.map((w) => w.bytes.first), [0x69, 0x6A]);
    expect(transport.writes.last.bytes.sublist(0, 4), [0x6A, 0x01, 0, 0]);
    expect(find.text('Real-time heart rate 72 bpm'), findsOneWidget);
    expect(find.text('Ring acknowledged stop 0x6A'), findsOneWidget);
    expect(
      find.text(
        'Stop 0x6A sent. Heart rate readings before it: 1, after it: 0.',
      ),
      findsOneWidget,
    );

    transport.emit(v1([0x69, 0x01, 0x00, 75]));
    await tester.pumpAndSettle();

    expect(find.text('Real-time heart rate 75 bpm'), findsOneWidget);
    expect(
      find.text(
        'Stop 0x6A sent. Heart rate readings before it: 1, after it: 1.',
      ),
      findsOneWidget,
    );
    expect(transport.writes, hasLength(2));
  });

  testWidgets('heart rate then stop waits while the reading is zero', (
    tester,
  ) async {
    final transport = FakeBleTransport();
    await pumpLab(tester, transport: transport);
    await scanAndConnect(tester);

    await tapKey(tester, ProtocolLabScreen.stopProbeKey);
    transport.emit(v1([0x69, 0x01, 0x00, 0]));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Waiting for a heart rate above zero before sending stop 0x6A. '
        'Readings so far: 1.',
      ),
      findsOneWidget,
    );
    expect(transport.writes, hasLength(1));
  });

  testWidgets('device notify frames are decoded as they arrive', (
    tester,
  ) async {
    final transport = await connectedLab(tester);

    for (final head in [
      [0x73, 0x01],
      [0x73, 0x03],
      [0x73, 0x04],
      [0x73, 0x05, 0xA0],
      [0x73, 0x0C, 64, 1],
      [0x73, 0x12, 0, 0x1F, 0x40, 0, 0, 0x64, 0, 0x0B, 0xB8],
      [0x73, 0x2A, 0xDE, 0xAD],
    ]) {
      transport.emit(v1(head));
    }
    await tester.pumpAndSettle();

    for (final line in [
      'Device notify 0x01: heart rate',
      'Device notify 0x03: SpO2',
      'Device notify 0x04: steps',
      'Device notify 0x05: temperature',
      'Provisional 36.0 °C (byte / 10 + 20)',
      'Payload a0 00 00 00 00 00 00 00 00 00 00 00 00',
      'Device notify 0x0C: battery',
      'Battery 64%, charging',
      'Device notify 0x12: live activity',
      '8000 steps, 100 cal, 3000 m',
      'Device notify 0x2A: unknown type',
      'Payload de ad 00 00 00 00 00 00 00 00 00 00 00',
    ]) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    expect(find.text('New data is waiting on the ring'), findsNWidgets(3));
    expect(transport.writes, isEmpty);
  });

  testWidgets('reads in German', (tester) async {
    await pumpLab(tester, locale: const Locale('de'));

    expect(find.text('Protokoll-Labor'), findsOneWidget);
    expect(find.text('Akku auslesen'), findsOneWidget);
  });
}
