import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/application/protocol_lab_controller.dart';
import 'package:open_ring/features/ring/application/protocol_lab_state.dart';
import 'package:open_ring/features/ring/domain/checksum_rule.dart';
import 'package:open_ring/features/ring/domain/frame_log_entry.dart';
import 'package:open_ring/features/ring/domain/raw_frame.dart';
import 'package:open_ring/features/ring/domain/session_log_exporter.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:ring_driver/testing.dart';
import 'package:ring_protocol/ring_protocol.dart';

import '../../../helpers/colmi_frames.dart';
import '../../../helpers/protocol_lab_fakes.dart';

class Harness {
  new({
    FakeBleTransport? transport,
    FakeRingScanner? scanner,
    RecordingExporter? exporter,
  }) : transport = transport ?? FakeBleTransport(responder: batteryResponder),
       scanner = scanner ?? FakeRingScanner(found: sampleDevices),
       exporter = exporter ?? RecordingExporter() {
    container = ProviderContainer(
      overrides: protocolLabOverrides(
        transport: this.transport,
        scanner: this.scanner,
        exporter: this.exporter,
      ),
    );
    container.listen(protocolLabProvider, (_, _) {});
  }

  final FakeBleTransport transport;
  final FakeRingScanner scanner;
  final RecordingExporter exporter;
  late final ProviderContainer container;

  ProtocolLabState get state => container.read(protocolLabProvider);
  ProtocolLabController get lab => container.read(protocolLabProvider.notifier);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> connected() async {
    await lab.connect(sampleDevices[1]);
    await settle();
  }

  void dispose() => container.dispose();
}

void main() {
  late Harness h;

  setUp(() => h = Harness());
  tearDown(() => h.dispose());

  group('scan', () {
    test('lists Colmi looking devices first', () async {
      await h.lab.startScan();
      await h.settle();

      expect(h.state.scanning, isTrue);
      expect(h.state.devices.map((d) => d.id), [
        'AA:BB:CC:00:00:03',
        'AA:BB:CC:00:00:02',
        'AA:BB:CC:00:00:01',
      ]);
      expect(h.scanner.starts, 1);
    });

    test('stop clears the scanning flag', () async {
      await h.lab.startScan();
      await h.lab.stopScan();
      await h.settle();

      expect(h.state.scanning, isFalse);
    });

    test('a scan failure becomes a notice', () async {
      h.dispose();
      h = Harness(
        scanner: FakeRingScanner(
          failure: const BleTransportException('Bluetooth adapter is off'),
        ),
      );

      await h.lab.startScan();

      expect(
        h.state.notice,
        isA<TransportFailure>().having(
          (n) => n.message,
          'message',
          'Bluetooth adapter is off',
        ),
      );
    });
  });

  group('connect', () {
    test('stops the scan and connects to the chosen device', () async {
      await h.lab.startScan();
      await h.connected();

      expect(h.scanner.stops, 1);
      expect(h.transport.deviceId, 'AA:BB:CC:00:00:02');
      expect(h.state.link, TransportState.connected);
      expect(h.state.device, sampleDevices[1]);
    });

    test('an unreachable ring leaves a notice and no link', () async {
      h.dispose();
      h = Harness(transport: FakeBleTransport(unreachable: true));

      await h.connected();

      expect(h.state.link, TransportState.disconnected);
      expect(h.state.notice, isA<TransportFailure>());
    });

    test('disconnect drops the link', () async {
      await h.connected();
      await h.lab.disconnect();
      await h.settle();

      expect(h.state.link, TransportState.disconnected);
      expect(h.transport.deviceId, isNull);
    });
  });

  group('commands', () {
    test('battery logs the request then the reply, in order', () async {
      await h.connected();

      await h.lab.readBattery();
      await h.settle();

      final request = [0x03, ...List.filled(14, 0), 0x03];
      expect(h.transport.writes, [GattPacket(v1Write, request)]);
      expect(h.state.log, [
        FrameLogEntry(
          at: labEpoch,
          direction: FrameDirection.tx,
          characteristic: ColmiGatt.v1Write,
          bytes: request,
        ),
        FrameLogEntry(
          at: labEpoch.add(const Duration(milliseconds: 250)),
          direction: FrameDirection.rx,
          characteristic: ColmiGatt.v1Notify,
          bytes: batteryReply,
        ),
      ]);
    });

    test('find device sends 0x50 0x55 0xAA with the chosen checksum', () async {
      await h.connected();

      await h.lab.findDevice();
      h.lab.selectChecksum(ChecksumRule.modulo255);
      await h.lab.findDevice();

      final frames = h.transport.writes.map((w) => w.bytes).toList();
      expect(frames.map((f) => f.sublist(0, 3)), [
        [0x50, 0x55, 0xAA],
        [0x50, 0x55, 0xAA],
      ]);
      expect(frames.map((f) => f.last), [0x4F, 0x50]);
      expect(h.state.checksum, ChecksumRule.modulo255);
    });

    test('a raw frame goes out exactly as typed', () async {
      await h.connected();

      await h.lab.sendRaw('69 01 01 00 00 00 00 00 00 00 00 00 00 00 00 6b');

      expect(h.transport.writes.single.bytes, [
        0x69,
        0x01,
        0x01,
        ...List.filled(12, 0),
        0x6B,
      ]);
      expect(h.state.log.single.direction, FrameDirection.tx);
    });

    for (final command in ['08', 'ff']) {
      test('a raw 0x$command frame is refused and never written', () async {
        await h.connected();

        await h.lab.sendRaw('$command${'00' * 15}');

        expect(h.transport.writes, isEmpty);
        expect(h.state.log, isEmpty);
        expect(
          h.state.notice,
          isA<RawFrameRejected>().having(
            (n) => n.error,
            'error',
            RawFrameError.blockedCommand,
          ),
        );
      });
    }

    test('a short raw frame reports its length', () async {
      await h.connected();

      await h.lab.sendRaw('03 00');

      expect(
        h.state.notice,
        isA<RawFrameRejected>()
            .having((n) => n.error, 'error', RawFrameError.wrongLength)
            .having((n) => n.byteCount, 'byteCount', 2),
      );
    });

    test('a failed write is a notice, not a logged frame', () async {
      await h.lab.readBattery();

      expect(h.state.log, isEmpty);
      expect(h.state.notice, isA<TransportFailure>());
    });

    test('the next command clears an old notice', () async {
      await h.connected();
      await h.lab.sendRaw('zz');
      expect(h.state.notice, isNotNull);

      await h.lab.readBattery();

      expect(h.state.notice, isNull);
    });
  });

  group('verification commands', () {
    test('set time sends the local clock with the chosen checksum', () async {
      await h.connected();
      h.lab.selectChecksum(ChecksumRule.modulo255);

      await h.lab.setTime();

      expect(
        h.transport.writes.single.bytes,
        setTimeRequest(labEpoch.toLocal(), codec: ChecksumRule.modulo255.codec),
      );
    });

    test('each auto monitor is read with action 1 and never written', () async {
      await h.connected();

      for (final monitor in AutoMonitor.values) {
        await h.lab.readAutoMonitor(monitor);
      }

      expect(h.transport.writes.map((w) => w.bytes.sublist(0, 3)), [
        [0x2C, 0x01, 0x00],
        [0x36, 0x01, 0x00],
        [0x38, 0x01, 0x00],
      ]);
    });

    test("today's totals is the bare 0x48 request", () async {
      await h.connected();

      await h.lab.readTodayTotals();

      expect(h.transport.writes.single.bytes, todayTotalsRequest());
    });
  });

  group('stop probe', () {
    test('sends 0x6A after the first heart rate above zero', () async {
      await h.connected();

      await h.lab.startStopProbe();
      expect(h.transport.writes.single.bytes.sublist(0, 3), [0x69, 1, 1]);
      expect(h.state.stopProbe, const StopProbe());

      h.transport.emit(v1([0x69, 0x01, 0x00, 0]));
      await h.settle();
      expect(h.transport.writes, hasLength(1));
      expect(h.state.stopProbe, const StopProbe(before: 1));

      h.transport.emit(v1([0x69, 0x01, 0x00, 72]));
      await h.settle();
      expect(
        h.transport.writes.last.bytes,
        realTimeStopRequest(RealTimeType.heartRate),
      );
      expect(h.state.stopProbe, const StopProbe(stopSent: true, before: 2));

      h.transport.emit(v1([0x69, 0x01, 0x00, 74]));
      await h.settle();
      expect(h.transport.writes, hasLength(2));
      expect(
        h.state.stopProbe,
        const StopProbe(stopSent: true, before: 2, after: 1),
      );
      expect(h.state.log.map((e) => (e.direction, e.bytes.first, e.bytes[3])), [
        (FrameDirection.tx, 0x69, 0),
        (FrameDirection.rx, 0x69, 0),
        (FrameDirection.rx, 0x69, 72),
        (FrameDirection.tx, 0x6A, 0),
        (FrameDirection.rx, 0x69, 74),
      ]);
    });

    test('an error reading does not send the stop', () async {
      await h.connected();
      await h.lab.startStopProbe();

      h.transport.emit(v1([0x69, 0x01, 0x02, 60]));
      await h.settle();

      expect(h.transport.writes, hasLength(1));
      expect(h.state.stopProbe, const StopProbe(before: 1));
    });

    test('a reading of another type is not counted', () async {
      await h.connected();
      await h.lab.startStopProbe();

      h.transport.emit(v1([0x69, 0x03, 0x00, 97]));
      await h.settle();

      expect(h.transport.writes, hasLength(1));
      expect(h.state.stopProbe, const StopProbe());
    });

    test('starting again resets the counts', () async {
      await h.connected();
      await h.lab.startStopProbe();
      h.transport.emit(v1([0x69, 0x01, 0x00, 72]));
      await h.settle();

      await h.lab.startStopProbe();

      expect(h.state.stopProbe, const StopProbe());
    });

    test('no reading is counted before a probe starts', () async {
      await h.connected();

      h.transport.emit(v1([0x69, 0x01, 0x00, 72]));
      await h.settle();

      expect(h.state.stopProbe, isNull);
      expect(h.transport.writes, isEmpty);
    });
  });

  group('notifications', () {
    test('frames from both notify characteristics are logged', () async {
      await h.connected();

      h.transport
        ..emit(GattPacket(bigDataNotify, const [0xBC, 0x27, 0x00, 0x10]))
        ..emit(GattPacket(v1Notify, batteryReply));
      await h.settle();

      expect(h.state.log.map((e) => e.characteristic), [
        ColmiGatt.bigDataNotify,
        ColmiGatt.v1Notify,
      ]);
      expect(
        h.state.log.every((e) => e.direction == FrameDirection.rx),
        isTrue,
      );
    });

    test('nothing is logged after disconnect', () async {
      await h.connected();
      await h.lab.disconnect();
      await h.settle();

      h.transport.emit(GattPacket(v1Notify, batteryReply));
      await h.settle();

      expect(h.state.log, isEmpty);
    });

    test('a reconnect does not log each frame twice', () async {
      await h.connected();
      await h.lab.disconnect();
      await h.settle();
      await h.connected();

      h.transport.emit(GattPacket(v1Notify, batteryReply));
      await h.settle();

      expect(h.state.log, hasLength(1));
    });
  });

  group('log', () {
    test(
      'export hands the JSON lines and a file name to the exporter',
      () async {
        await h.connected();
        await h.lab.readBattery();
        await h.settle();

        await h.lab.exportLog();

        final export = h.exporter.exports.single;
        expect(
          export.fileName,
          matches(RegExp(r'^openring-lab-\d{8}-\d{6}Z\.jsonl$')),
        );
        expect(SessionLog.decode(export.contents), h.state.log);
      },
    );

    test('export does nothing for an empty log', () async {
      await h.lab.exportLog();

      expect(h.exporter.exports, isEmpty);
    });

    test('an export failure becomes a notice', () async {
      h.dispose();
      h = Harness(
        exporter: RecordingExporter(
          failure: const SessionLogExportException('no share target'),
        ),
      );
      await h.connected();
      await h.lab.readBattery();

      await h.lab.exportLog();

      expect(
        h.state.notice,
        isA<ExportFailure>().having(
          (n) => n.message,
          'message',
          'no share target',
        ),
      );
    });

    test('clear empties the log', () async {
      await h.connected();
      await h.lab.readBattery();
      await h.settle();

      h.lab.clearLog();

      expect(h.state.log, isEmpty);
    });

    test('the export file name uses UTC', () {
      expect(
        ProtocolLabController.exportFileName(DateTime.utc(2026, 1, 2, 3, 4, 5)),
        'openring-lab-20260102-030405Z.jsonl',
      );
    });
  });
}
