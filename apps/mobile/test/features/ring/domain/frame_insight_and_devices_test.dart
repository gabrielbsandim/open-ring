import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/domain/checksum_rule.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/features/ring/domain/frame_insight.dart';
import 'package:open_ring/features/ring/domain/frame_log_entry.dart';
import 'package:ring_protocol/ring_protocol.dart';

List<int> masked(List<int> head) {
  final body = [...head, ...List.filled(15 - head.length, 0)];
  return [...body, const MaskedSumChecksum().compute(body)];
}

List<int> hex(String text) => [
  for (final byte in text.trim().split(RegExp(r'\s+')))
    int.parse(byte, radix: 16),
];

FrameLogEntry entry(FrameDirection direction, List<int> bytes) => FrameLogEntry(
  at: DateTime.utc(2026, 11, 10),
  direction: direction,
  characteristic: ColmiGatt.v1Notify,
  bytes: bytes,
);

void main() {
  group('ChecksumRule', () {
    test('the find device frame tells the two rules apart', () {
      final masked = ChecksumRule.masked.codec.encode(V1Command.findDevice, [
        0x55,
        0xAA,
      ]);
      final modulo = ChecksumRule.modulo255.codec.encode(V1Command.findDevice, [
        0x55,
        0xAA,
      ]);

      expect(masked.sublist(0, 3), [0x50, 0x55, 0xAA]);
      expect(masked.last, 0x4F);
      expect(modulo.last, 0x50);
    });
  });

  group('FrameInsight', () {
    test('decodes a battery reply and reports both matching rules', () {
      final insight = FrameInsight.of(
        entry(FrameDirection.rx, [0x03, 80, 1, ...List.filled(12, 0), 84]),
      );

      expect(
        insight?.battery,
        const BatteryReading(percent: 80, charging: true),
      );
      expect(insight?.checksums, ChecksumRule.values.toSet());
    });

    test('names the only rule a frame satisfies', () {
      final frame = ChecksumRule.modulo255.codec.encode(V1Command.findDevice, [
        0x55,
        0xAA,
      ]);

      final insight = FrameInsight.of(entry(FrameDirection.rx, frame));

      expect(insight?.checksums, {ChecksumRule.modulo255});
      expect(insight?.battery, isNull);
    });

    test('reports no rule when the checksum is wrong', () {
      final insight = FrameInsight.of(
        entry(FrameDirection.rx, [0x03, 80, 0, ...List.filled(12, 0), 0x99]),
      );

      expect(insight?.checksums, isEmpty);
      expect(insight?.battery, isNull);
    });

    test('never reads a sent battery request as a battery level', () {
      final request = ChecksumRule.masked.codec.encode(V1Command.battery);

      final insight = FrameInsight.of(entry(FrameDirection.tx, request));

      expect(insight?.battery, isNull);
      expect(insight?.checksums, ChecksumRule.values.toSet());
    });

    test('skips frames that are not 16 bytes', () {
      expect(
        FrameInsight.of(entry(FrameDirection.rx, [0xBC, 0x27, 0, 0])),
        isNull,
      );
    });
  });

  group('FrameInsight readings', () {
    FrameReading? read(List<int> head) =>
        FrameInsight.of(entry(FrameDirection.rx, masked(head)))?.reading;

    test('a set time reply carries the capability flags', () {
      final reading = read(hex('01 00 01 00 22 00 00 00 00 01 00 30 01 00 10'));

      expect(
        reading,
        isA<CapabilitiesFrame>().having(
          (r) => r.capabilities.supportsBloodOxygen,
          'blood oxygen',
          isTrue,
        ),
      );
    });

    for (final (id, monitor) in [
      (0x2C, AutoMonitor.spo2),
      (0x36, AutoMonitor.stress),
      (0x38, AutoMonitor.hrv),
    ]) {
      test('a 0x${id.toRadixString(16)} read reply keeps the raw byte', () {
        expect(
          read([id, 0x01, 0x01]),
          isA<AutoMonitorFrame>()
              .having((r) => r.monitor, 'monitor', monitor)
              .having((r) => r.enabled, 'enabled', isTrue)
              .having((r) => r.rawValue, 'raw', 1),
        );
      });
    }

    test('a setting reply with another action names the odd byte', () {
      expect(
        read([0x36, 0x02, 0x01]),
        isA<UnexpectedByteFrame>()
            .having((r) => r.command, 'command', 0x36)
            .having((r) => r.index, 'index', 1)
            .having((r) => r.value, 'value', 2),
      );
    });

    test('today totals are read in both byte orders', () {
      final reading = read([0x48, 0x00, 0x1F, 0x40]);

      expect(
        reading,
        isA<TodayTotalsFrame>()
            .having((r) => r.bigEndian.totalSteps, 'big', 0x001F40)
            .having((r) => r.littleEndian.totalSteps, 'little', 0x401F00),
      );
    });

    test('a 0x69 frame is a real-time reading', () {
      expect(
        read([0x69, 0x01, 0x00, 72]),
        isA<RealTimeFrame>().having(
          (r) => r.reading,
          'reading',
          const RealTimeReading(
            type: RealTimeType.heartRate,
            errorCode: 0,
            value: 72,
          ),
        ),
      );
    });

    test('a 0x6A frame acknowledges the stop', () {
      expect(read([0x6A, 0x01]), isA<RealTimeStopFrame>());
    });

    test('a 0x73 frame is a device notification', () {
      expect(
        read([0x73, 0x0C, 64, 0]),
        isA<NotifyFrame>().having(
          (r) => r.notification,
          'notification',
          const BatteryNotification(percent: 64, charging: false),
        ),
      );
    });

    test('bit 7 on a known command reads as a flagged reply', () {
      expect(
        read([0x2C | V1Frame.errorBit]),
        isA<FlaggedReplyFrame>().having((r) => r.command, 'command', 0xAC),
      );
    });

    test('a 16 byte big data frame is not read as a flagged reply', () {
      expect(read([0xBC, 0x27, 0x00, 0x00]), isNull);
    });

    test('a sent frame is never read', () {
      final insight = FrameInsight.of(entry(FrameDirection.tx, masked([0x48])));

      expect(insight?.reading, isNull);
    });
  });

  group('DiscoveredDevice', () {
    test('a R0x name or the V1 service marks a Colmi ring', () {
      expect(
        const DiscoveredDevice(
          id: 'a',
          name: 'R02_A1B2',
          rssi: -50,
        ).looksLikeColmi,
        isTrue,
      );
      expect(
        const DiscoveredDevice(
          id: 'a',
          name: 'r09_c0fe',
          rssi: -50,
        ).looksLikeColmi,
        isTrue,
      );
      expect(
        const DiscoveredDevice(
          id: 'a',
          name: 'COLMI R09',
          rssi: -50,
        ).looksLikeColmi,
        isTrue,
      );
      expect(
        const DiscoveredDevice(
          id: 'a',
          name: '',
          rssi: -50,
          serviceUuids: ['6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E'],
        ).looksLikeColmi,
        isTrue,
      );
      expect(
        const DiscoveredDevice(
          id: 'a',
          name: 'R10 speaker',
          rssi: -50,
        ).looksLikeColmi,
        isFalse,
      );
    });

    test('ranks Colmi devices first, then by signal strength', () {
      final ranked = DiscoveredDevice.rank(const [
        DiscoveredDevice(id: 'tv', name: 'TV', rssi: -30),
        DiscoveredDevice(id: 'far', name: 'R09_0001', rssi: -90),
        DiscoveredDevice(id: 'watch', name: 'Watch', rssi: -60),
        DiscoveredDevice(
          id: 'near',
          name: '',
          rssi: -45,
          serviceUuids: [ColmiGatt.v1Service],
        ),
      ]);

      expect(ranked.map((d) => d.id), ['near', 'far', 'tv', 'watch']);
    });
  });
}
