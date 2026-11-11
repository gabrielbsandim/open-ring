import 'dart:async';

import 'package:ring_driver/ring_driver.dart';
import 'package:ring_driver/testing.dart';
import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

List<int> hex(String text) => [
  for (final byte in text.trim().split(RegExp(r'\s+')))
    int.parse(byte, radix: 16),
];

List<int> padded(List<int> head) {
  final body = [...head, ...List.filled(15 - head.length, 0)];
  return [...body, const MaskedSumChecksum().compute(body)];
}

GattPacket v1(List<int> bytes) =>
    GattPacket(ColmiDriver.notify, bytes.length == 16 ? bytes : padded(bytes));

List<GattPacket> bigData(int id, List<int> payload, {int chunk = 20}) {
  final crc = crc16Modbus(payload);
  final bytes = [
    0xBC,
    id,
    payload.length & 0xFF,
    payload.length >> 8,
    crc & 0xFF,
    crc >> 8,
    ...payload,
  ];
  return [
    for (var i = 0; i < bytes.length; i += chunk)
      GattPacket(
        ColmiDriver.bigDataNotify,
        bytes.sublist(i, (i + chunk).clamp(0, bytes.length)),
      ),
  ];
}

String byteHex(int value) => value.toRadixString(16).padLeft(2, '0');

// tahnok tests/test_hr.py HEART_RATE_PACKETS, a capture for 2024-08-10.
final List<String> tahnokHeartRate = [
  '15 00 18 05 00 00 00 00 00 00 00 00 00 00 00 32',
  '15 01 80 ad b6 66 00 00 00 00 00 00 00 00 00 5f',
  for (var i = 2; i <= 0x0e; i++)
    '15 ${byteHex(i)} 00 00 00 00 00 00 00 00 00 00 00 00 00 ${byteHex(0x15 + i)}',
  '15 0f 00 00 59 00 00 00 00 00 00 00 00 00 00 7d',
  '15 10 00 6b 00 00 00 00 00 00 00 00 00 00 00 90',
  '15 11 60 00 00 00 00 00 00 00 00 00 00 00 6b f1',
  '15 12 00 00 00 00 00 00 00 00 00 00 00 00 00 27',
  '15 13 00 00 00 00 00 00 00 00 00 00 50 00 00 78',
  '15 14 00 00 00 00 00 00 00 00 00 46 00 00 00 6f',
  '15 15 00 00 00 00 00 00 00 00 00 00 00 00 00 2a',
  '15 16 00 00 00 00 00 00 00 00 00 00 00 00 00 2b',
  '15 17 00 00 00 00 00 00 00 00 00 00 00 00 00 2c',
];

typedef Harness = ({FakeBleTransport transport, ColmiDriver driver});

Future<Harness> connected(
  FakeResponder responder, {
  DateTime? now,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final transport = FakeBleTransport(responder: responder);
  final driver = ColmiDriver(
    transport: transport,
    clock: () => now ?? DateTime(2024, 8, 10, 23, 59),
    responseTimeout: timeout,
  );
  addTearDown(() async {
    await driver.close();
    await transport.close();
  });
  await driver.connect('R09_ABCD');
  return (transport: transport, driver: driver);
}

Iterable<GattPacket> none(GattPacket write) => const [];

void main() {
  group('link', () {
    test(
      'connect reports connecting then connected and sets the identity',
      () async {
        final transport = FakeBleTransport();
        final driver = ColmiDriver(transport: transport);
        addTearDown(() async {
          await driver.close();
          await transport.close();
        });

        final states = driver.linkState.take(2).toList();
        await driver.connect('R09_ABCD');

        expect(await states, [
          RingLinkState.connecting,
          RingLinkState.connected,
        ]);
        expect(driver.identity.deviceId, 'R09_ABCD');
        expect(driver.identity.model, 'R09');
        expect(driver.capabilities, contains(RingCapability.sleep));
      },
    );

    test('disconnect reports disconnecting then disconnected', () async {
      final h = await connected(none);
      final states = h.driver.linkState.take(2).toList();

      await h.driver.disconnect();

      expect(await states, [
        RingLinkState.disconnecting,
        RingLinkState.disconnected,
      ]);
    });

    test('an unreachable ring surfaces the transport error', () async {
      final transport = FakeBleTransport(unreachable: true);
      final driver = ColmiDriver(transport: transport);
      addTearDown(() async {
        await driver.close();
        await transport.close();
      });

      await expectLater(
        driver.connect('R09_ABCD'),
        throwsA(isA<BleTransportException>()),
      );
    });
  });

  group('single frame commands', () {
    test(
      'syncTime writes the tahnok frame and keeps the capability reply',
      () async {
        final h = await connected(
          (w) => [v1(hex('01 00 01 00 22 00 00 00 00 01 00 30 01 00 10 66'))],
        );

        await h.driver.syncTime(DateTime(2024));

        expect(
          h.transport.writes.single,
          GattPacket(
            ColmiDriver.write,
            hex('01 24 01 01 00 00 00 01 00 00 00 00 00 00 00 28'),
          ),
        );
        expect(h.driver.reportedCapabilities?.supportsBloodOxygen, isTrue);
      },
    );

    test('readHeartRateInterval reads the auto heart rate setting', () async {
      final h = await connected(
        (w) => [
          v1([0x16, 0x01, 0x01, 0x1E]),
        ],
      );

      final interval = await h.driver.readHeartRateInterval();

      expect(interval, const Duration(minutes: 30));
      expect(h.transport.writes.single.bytes, padded([0x16, 0x01]));
    });

    test('readHeartRateInterval is null when the ring has it off', () async {
      final h = await connected(
        (w) => [
          v1([0x16, 0x01, 0x02, 0x1E]),
        ],
      );

      expect(await h.driver.readHeartRateInterval(), isNull);
    });

    test('setHeartRateInterval writes enabled and the minutes', () async {
      final h = await connected(
        (w) => [
          v1([0x16, 0x02, 0x01, 0x05]),
        ],
      );

      await h.driver.setHeartRateInterval(const Duration(minutes: 5));

      expect(h.transport.writes.single.bytes, padded([0x16, 0x02, 0x01, 0x05]));
    });

    test('setHeartRateInterval writes 2 to turn the log off', () async {
      final h = await connected(
        (w) => [
          v1([0x16, 0x02, 0x02, 0x05]),
        ],
      );

      await h.driver.setHeartRateInterval(
        const Duration(minutes: 5),
        enabled: false,
      );

      expect(h.transport.writes.single.bytes, padded([0x16, 0x02, 0x02, 0x05]));
    });

    test('readMonitor reads each auto monitor setting', () async {
      final h = await connected(
        (w) => [
          v1([w.bytes.first, 0x01, if (w.bytes.first != 0x36) 0x01]),
        ],
      );

      expect(await h.driver.readMonitor(RingMonitor.spo2), isTrue);
      expect(await h.driver.readMonitor(RingMonitor.stress), isFalse);
      expect(await h.driver.readMonitor(RingMonitor.hrv), isTrue);
      expect(
        [for (final w in h.transport.writes) w.bytes],
        [
          padded([0x2C, 0x01]),
          padded([0x36, 0x01]),
          padded([0x38, 0x01]),
        ],
      );
    });

    test('setMonitor writes 1 on and 0 off', () async {
      final h = await connected(
        (w) => [
          v1([w.bytes.first, 0x02]),
        ],
      );

      await h.driver.setMonitor(RingMonitor.hrv, enabled: true);
      await h.driver.setMonitor(RingMonitor.spo2, enabled: false);

      expect(
        [for (final w in h.transport.writes) w.bytes],
        [
          padded([0x38, 0x02, 0x01]),
          padded([0x2C, 0x02, 0x00]),
        ],
      );
    });

    test('readBattery maps the tahnok battery reply', () async {
      final h = await connected(
        (w) => [v1(hex('03 40 00 00 00 00 00 00 00 00 00 00 00 00 00 43'))],
      );

      final battery = await h.driver.readBattery();

      expect(battery.percent, 64);
      expect(battery.charging, isFalse);
      expect(h.transport.writes.single.bytes, padded([0x03]));
    });

    test('ignores pushes from other commands while waiting', () async {
      final h = await connected(
        (w) => [
          v1(hex('2f f1 00 00 00 00 00 00 00 00 00 00 00 00 00 20')),
          v1(hex('73 0c 2b 01 00 00 00 00 00 00 00 00 00 00 00 ab')),
          v1([0x03, 90, 1]),
        ],
      );

      final battery = await h.driver.readBattery();

      expect(battery.percent, 90);
      expect(battery.charging, isTrue);
    });

    test('an error response throws with the parse error', () async {
      final h = await connected(
        (w) => [
          v1([0x83]),
        ],
      );

      await expectLater(
        h.driver.readBattery(),
        throwsA(
          isA<ColmiProtocolException>().having(
            (e) => e.error,
            'error',
            const ErrorResponse(0x83),
          ),
        ),
      );
    });

    test('a reply with a bad checksum throws a checksum mismatch', () async {
      final h = await connected(
        (w) => [v1(hex('03 40 00 00 00 00 00 00 00 00 00 00 00 00 00 44'))],
      );

      await expectLater(
        h.driver.readBattery(),
        throwsA(
          isA<ColmiProtocolException>().having(
            (e) => e.error,
            'error',
            isA<ChecksumMismatch>(),
          ),
        ),
      );
    });

    test('no reply times out', () async {
      final h = await connected(
        none,
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        h.driver.readBattery(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('findDevice writes 0x50 0x55 0xAA and waits for the echo', () async {
      final h = await connected(
        (w) => [
          v1([0x50]),
        ],
      );

      await h.driver.findDevice();

      expect(h.transport.writes.single.bytes, padded([0x50, 0x55, 0xAA]));
    });
  });

  group('history', () {
    test(
      'pullHeartRate sends local midnight and maps the tahnok capture',
      () async {
        final h = await connected(
          (w) => w.bytes.first == 0x15
              ? tahnokHeartRate.map((line) => v1(hex(line)))
              : const [],
        );

        final samples = await h.driver.pullHeartRate(DateTime(2024, 8, 10));

        expect(
          h.transport.writes.single.bytes,
          padded([0x15, 0x80, 0xAD, 0xB6, 0x66]),
        );
        expect(samples.map((s) => (s.at.hour, s.at.minute, s.bpm)), [
          (15, 0, 89),
          (16, 0, 107),
          (17, 0, 96),
          (18, 0, 107),
          (20, 0, 80),
          (21, 0, 70),
        ]);
        expect(samples.first.at, DateTime(2024, 8, 10, 15));
      },
    );

    test('pullHeartRate drops slots later than now', () async {
      final h = await connected(
        (w) => tahnokHeartRate.map((line) => v1(hex(line))),
        now: DateTime(2024, 8, 10, 17, 30),
      );

      final samples = await h.driver.pullHeartRate(DateTime(2024, 8, 10));

      expect(samples.map((s) => s.bpm), [89, 107, 96]);
    });

    test('pullHeartRate asks once per day back to since', () async {
      final h = await connected(
        (w) => [
          v1([0x15, 0xFF]),
        ],
      );

      final samples = await h.driver.pullHeartRate(DateTime(2024, 8, 8, 12));

      expect(samples, isEmpty);
      final days = h.transport.writes
          .map((w) => w.bytes.sublist(1, 5))
          .map((b) => b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24)
          .toList();
      expect(days, [1723248000, 1723248000 - 86400, 1723248000 - 2 * 86400]);
    });

    test('pullActivity maps the tahnok single record capture', () async {
      final h = await connected(
        (w) => [
          v1(hex('43 f0 01 01 00 00 00 00 00 00 00 00 00 00 00 35')),
          v1(hex('43 24 10 15 5c 00 01 79 00 15 00 10 00 00 00 87')),
        ],
        now: DateTime(2024, 10, 15, 23, 59),
      );

      final buckets = await h.driver.pullActivity(DateTime(2024, 10, 15));

      expect(
        h.transport.writes.single.bytes,
        padded([0x43, 0, 0x0F, 0, 0x5F, 1]),
      );
      final bucket = buckets.single;
      expect(bucket.start, DateTime(2024, 10, 15, 23));
      expect(bucket.duration, const Duration(minutes: 15));
      expect(bucket.steps, 21);
      expect(bucket.distanceMeters, 16);
      expect(bucket.activeKilocalories, closeTo(1.21, 1e-9));
    });

    test(
      'pullActivity walks day offsets and stops at the history limit',
      () async {
        final h = await connected(
          (w) => [
            v1([0x43, 0xFF]),
          ],
        );

        await h.driver.pullActivity(DateTime(2024));

        expect(h.transport.writes.map((w) => w.bytes[1]), [
          0,
          1,
          2,
          3,
          4,
          5,
          6,
        ]);
      },
    );

    List<GattPacket> halfHourly(int id) => [
      v1([id, 0, 5, 30]),
      v1([id, 1, 0, 40, ...List.filled(10, 0), 41]),
      v1([id, 2, 42]),
      v1([id, 3]),
      v1([id, 4, ...List.filled(12, 0), 43]),
    ];

    test('pullStress reads today and drops slots past midnight', () async {
      final h = await connected((w) => halfHourly(0x37));

      final samples = await h.driver.pullStress(DateTime(2024, 8, 10));

      expect(h.transport.writes.single.bytes, padded([0x37]));
      expect(samples.map((s) => (s.at, s.level)), [
        (DateTime(2024, 8, 10), 40),
        (DateTime(2024, 8, 10, 5, 30), 41),
        (DateTime(2024, 8, 10, 6), 42),
      ]);
    });

    test('pullHrv sends days ago and maps half hour slots', () async {
      final h = await connected(
        (w) => w.bytes[1] == 1
            ? halfHourly(0x39)
            : [
                v1([0x39, 0xFF]),
              ],
      );

      final samples = await h.driver.pullHrv(DateTime(2024, 8, 9));

      expect(h.transport.writes.map((w) => w.bytes[1]), [0, 1]);
      expect(samples.first.at, DateTime(2024, 8, 9));
      expect(samples.map((s) => s.milliseconds), [40, 41, 42]);
    });

    test('pullSpo2 reassembles big data and averages each hour', () async {
      final payload = [
        1,
        for (var h = 0; h < 24; h++) ...[95, 99],
        0,
        96,
        98,
        0,
        0,
      ];
      final h = await connected(
        (w) => w.characteristic == ColmiDriver.bigDataWrite
            ? bigData(BigDataId.spo2, payload)
            : const [],
      );

      final samples = await h.driver.pullSpo2(DateTime(2024, 8, 9, 22));

      expect(
        h.transport.writes.single,
        GattPacket(ColmiDriver.bigDataWrite, hex('bc 2a 01 00 ff 00 ff')),
      );
      expect(samples.map((s) => (s.at, s.percent)), [
        (DateTime(2024, 8, 9, 22), 97),
        (DateTime(2024, 8, 9, 23), 97),
        (DateTime(2024, 8, 10), 97),
      ]);
    });

    test('pullSleep builds segments that start before midnight', () async {
      final payload = [
        1,
        0,
        12,
        0x64,
        0x05,
        0xA4,
        0x01,
        2,
        120,
        1,
        30,
        3,
        90,
        4,
        60,
      ];
      final h = await connected(
        (w) => bigData(BigDataId.sleep, payload, chunk: 7),
      );

      final segments = await h.driver.pullSleep(DateTime(2024, 8, 9));

      expect(segments.map((s) => (s.start, s.end, s.stage)), [
        (DateTime(2024, 8, 9, 23), DateTime(2024, 8, 10, 1), SleepStage.light),
        (
          DateTime(2024, 8, 10, 1, 30),
          DateTime(2024, 8, 10, 3),
          SleepStage.deep,
        ),
        (DateTime(2024, 8, 10, 3), DateTime(2024, 8, 10, 4), SleepStage.rem),
      ]);
    });

    test('a big data crc mismatch throws', () async {
      final h = await connected((w) {
        final packets = bigData(BigDataId.sleep, const [0]);
        final bytes = [...packets.single.bytes]..[4] ^= 0xFF;
        return [GattPacket(ColmiDriver.bigDataNotify, bytes)];
      });

      await expectLater(
        h.driver.pullSleep(DateTime(2024, 8, 9)),
        throwsA(
          isA<ColmiProtocolException>().having(
            (e) => e.error,
            'error',
            isA<ChecksumMismatch>(),
          ),
        ),
      );
    });

    test(
      'big data for another id is ignored until the asked one arrives',
      () async {
        final h = await connected(
          (w) => [
            ...bigData(BigDataId.temperature, const [0, 0x1E]),
            ...bigData(BigDataId.sleep, const [0]),
          ],
        );

        expect(await h.driver.pullSleep(DateTime(2024, 8, 9)), isEmpty);
      },
    );
  });

  group('live', () {
    test(
      'heart rate starts with type 1, skips errors and stops with 0x6A',
      () async {
        final h = await connected(
          (w) => w.bytes.first == 0x69
              ? [
                  v1(hex('69 01 01 00 00 00 00 00 00 00 00 00 00 00 00 6b')),
                  v1(hex('69 01 00 4e 00 00 00 00 00 00 00 00 00 00 00 b8')),
                  v1([0x69, 0x03, 0x00, 97]),
                ]
              : const [],
        );

        final reading = await h.driver.startLive(LiveKind.heartRate).first;
        await h.driver.stopLive();

        expect(reading.kind, LiveKind.heartRate);
        expect(reading.value, 78);
        expect(h.transport.writes.map((w) => w.bytes), [
          padded([0x69, 0x01, 0x01]),
          padded([0x6A, 0x01, 0x00, 0x00]),
        ]);
      },
    );

    test('SpO2 starts with type 3', () async {
      final h = await connected(
        (w) => [
          v1([0x69, 0x03, 0x00, 98]),
        ],
      );

      final reading = await h.driver.startLive(LiveKind.spo2).first;

      expect(reading.value, 98);
      expect(h.transport.writes.single.bytes, padded([0x69, 0x03, 0x01]));
    });

    test('stopLive without startLive writes nothing', () async {
      final h = await connected(none);

      await h.driver.stopLive();

      expect(h.transport.writes, isEmpty);
    });

    test('a failed start write surfaces on the stream', () async {
      final transport = FakeBleTransport();
      final driver = ColmiDriver(transport: transport);
      addTearDown(() async {
        await driver.close();
        await transport.close();
      });

      await expectLater(
        driver.startLive(LiveKind.heartRate),
        emitsError(isA<BleTransportException>()),
      );
    });
  });

  group('heart rate stream 0x1E', () {
    final enable = padded([0x1E, 0x01]);
    final disable = padded([0x1E, 0x02]);

    Future<({FakeBleTransport transport, ColmiDriver driver, Clock clock})>
    streaming({Duration keepAliveEvery = const Duration(minutes: 1)}) async {
      final transport = FakeBleTransport();
      final clock = Clock(DateTime(2026, 11, 10, 7));
      final driver = ColmiDriver(
        transport: transport,
        clock: () => clock.now,
        keepAliveEvery: keepAliveEvery,
      );
      addTearDown(() async {
        await driver.close();
        await transport.close();
      });
      await driver.connect('R09_ABCD');
      return (transport: transport, driver: driver, clock: clock);
    }

    List<List<int>> writes(FakeBleTransport transport) =>
        transport.writes.map((w) => w.bytes).toList();

    bool isKeepAlive(List<int> bytes) => bytes[0] == 0x1E && bytes[1] == 0x03;

    test('enables with 0x1E 0x01 and maps byte 1 to bpm', () async {
      final h = await streaming();
      final readings = <LiveReading>[];
      final sub = h.driver.startHeartRateStream().listen(readings.add);
      await pumpEventQueue();

      h.transport.emit(
        v1(hex('1e 50 00 00 00 00 00 00 00 00 00 00 00 00 00 6e')),
      );
      await pumpEventQueue();
      await sub.cancel();

      expect(writes(h.transport), [enable]);
      expect(readings.single.kind, LiveKind.heartRate);
      expect(readings.single.value, 80);
      expect(readings.single.at, DateTime(2026, 11, 10, 7));
    });

    test('keeps streaming past one reading, unlike 0x69', () async {
      final h = await streaming();
      final readings = <int>[];
      final sub = h.driver.startHeartRateStream().listen(
        (r) => readings.add(r.value),
      );
      await pumpEventQueue();

      for (final bpm in [80, 0, 82, 85, 88]) {
        h.transport
          ..emit(v1([0x1E, bpm]))
          ..emit(v1([0x69, 0x01, 0x00, 70]));
        await pumpEventQueue();
        h.clock.advance(const Duration(seconds: 1));
      }
      await sub.cancel();

      expect(readings, [80, 82, 85, 88]);
    });

    test('drops a reply in the same second as the previous one', () async {
      final h = await streaming();
      final readings = <int>[];
      final sub = h.driver.startHeartRateStream().listen(
        (r) => readings.add(r.value),
      );
      await pumpEventQueue();

      for (final (bpm, gap) in [(80, 300), (81, 800), (82, 1000), (83, 0)]) {
        h.transport.emit(v1([0x1E, bpm]));
        await pumpEventQueue();
        h.clock.advance(Duration(milliseconds: gap));
      }
      await sub.cancel();

      expect(readings, [80, 82, 83]);
    });

    test('sends continue on a timer and stops it with a disable', () async {
      final h = await streaming(
        keepAliveEvery: const Duration(milliseconds: 20),
      );
      final sub = h.driver.startHeartRateStream().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await h.driver.stopHeartRateStream();
      final atStop = writes(h.transport).length;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await sub.cancel();

      final sent = writes(h.transport);
      expect(sent.first, enable);
      expect(sent.last, disable);
      expect(sent.where(isKeepAlive).length, greaterThanOrEqualTo(2));
      expect(sent, hasLength(atStop));
    });

    test('the default continue period beats the 60 s ring timeout', () async {
      final h = await streaming();
      final sub = h.driver.startHeartRateStream().listen((_) {});
      await pumpEventQueue();
      await sub.cancel();

      expect(writes(h.transport), [enable]);
      expect(
        ColmiDriver.defaultKeepAliveEvery * 2,
        lessThan(continuousHeartRateTimeout),
      );
    });

    test('cancelling the stream stops the keep-alive', () async {
      final h = await streaming(
        keepAliveEvery: const Duration(milliseconds: 20),
      );
      final sub = h.driver.startHeartRateStream().listen((_) {});
      await pumpEventQueue();
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(writes(h.transport), [enable]);
    });

    test('stop without a stream writes nothing', () async {
      final h = await streaming();

      await h.driver.stopHeartRateStream();

      expect(h.transport.writes, isEmpty);
    });

    test('disconnect ends the keep-alive and needs no disable', () async {
      final h = await streaming(
        keepAliveEvery: const Duration(milliseconds: 20),
      );
      final errors = <Object>[];
      final sub = h.driver.startHeartRateStream().listen(
        (_) {},
        onError: errors.add,
      );
      await pumpEventQueue();
      await h.driver.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      await h.driver.stopHeartRateStream();
      await sub.cancel();

      expect(errors, isEmpty);
      expect(writes(h.transport), [enable]);
    });

    test('the 0x69 spot measure path ignores stream replies', () async {
      final h = await streaming();
      final reading = h.driver.startLive(LiveKind.heartRate).first;
      await pumpEventQueue();
      h.transport
        ..emit(v1([0x1E, 90]))
        ..emit(v1([0x69, 0x01, 0x00, 81]));

      expect((await reading).value, 81);
      expect(writes(h.transport), [
        padded([0x69, 0x01, 0x01]),
      ]);
    });

    test('a failed enable write surfaces on the stream', () async {
      final transport = FakeBleTransport();
      final driver = ColmiDriver(transport: transport);
      addTearDown(() async {
        await driver.close();
        await transport.close();
      });

      await expectLater(
        driver.startHeartRateStream(),
        emitsError(isA<BleTransportException>()),
      );
    });
  });
}

final class Clock {
  new(this.now);

  DateTime now;

  void advance(Duration by) => now = now.add(by);
}
