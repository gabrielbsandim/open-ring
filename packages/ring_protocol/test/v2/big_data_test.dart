import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

import '../helpers.dart';

List<int> packet(int id, List<int> payload) => [
  0xBC,
  id,
  payload.length & 0xFF,
  payload.length >> 8,
  crc16Modbus(payload) & 0xFF,
  crc16Modbus(payload) >> 8,
  ...payload,
];

void main() {
  group('crc16Modbus', () {
    test('matches the CRC-16/MODBUS check value for "123456789"', () {
      expect(crc16Modbus('123456789'.codeUnits), 0x4B37);
    });

    test('is 0xFFFF for an empty payload, as Puxtril requests carry', () {
      expect(crc16Modbus(const []), 0xFFFF);
    });
  });

  group('bigDataRequest', () {
    test('sleep request matches Gadgetbridge fetchHistorySleep', () {
      expect(bigDataRequest(BigDataId.sleep), hex('bc 27 01 00 ff 00 ff'));
    });

    test('SpO2 request matches Gadgetbridge fetchHistorySpo2', () {
      expect(bigDataRequest(BigDataId.spo2), hex('bc 2a 01 00 ff 00 ff'));
    });

    test('temperature request matches Gadgetbridge fetchTemperature', () {
      expect(
        bigDataRequest(BigDataId.temperature, temperatureRequestPayload),
        hex('bc 25 01 00 3e 81 02'),
      );
    });

    test(
      'empty payload gives length 0 and crc 0xFFFF (Puxtril BigDataRequest)',
      () {
        expect(
          bigDataRequest(BigDataId.sleep, BigDataFrame.puxtrilRequestPayload),
          hex('bc 27 00 00 ff ff'),
        );
      },
    );

    test('rejects an id or payload byte outside one byte', () {
      expect(() => bigDataRequest(0x100), throwsArgumentError);
      expect(() => bigDataRequest(0x27, [300]), throwsArgumentError);
    });
  });

  group('BigDataAssembler', () {
    final sleep = packet(0x27, List.generate(40, (i) => i));

    test('a packet in one notification parses at once', () {
      expect(
        BigDataAssembler().add(sleep),
        Parsed(BigDataPacket(0x27, List.generate(40, (i) => i))),
      );
    });

    test('reassembles a packet split over 20 byte notifications', () {
      final assembler = BigDataAssembler();
      expect(assembler.add(sleep.sublist(0, 20)), isNull);
      expect(assembler.add(sleep.sublist(20, 40)), isNull);
      expect(assembler.inProgress, isTrue);
      final result = assembler.add(sleep.sublist(40));
      expect((result! as Parsed<BigDataPacket>).value.payload.length, 40);
      expect(assembler.inProgress, isFalse);
    });

    test('waits for a header split across notifications', () {
      final assembler = BigDataAssembler();
      expect(assembler.add(sleep.sublist(0, 3)), isNull);
      expect(assembler.add(sleep.sublist(3)), isA<Parsed<BigDataPacket>>());
    });

    test('a truncated stream never completes', () {
      final assembler = BigDataAssembler();
      expect(assembler.add(sleep.sublist(0, sleep.length - 1)), isNull);
      expect(assembler.inProgress, isTrue);
    });

    test('bytes after a full packet start the next one', () {
      final assembler = BigDataAssembler();
      final spo2 = packet(0x2A, const [0, 97, 99]);
      final first = assembler.add([...sleep, ...spo2.sublist(0, 4)]);
      expect((first! as Parsed<BigDataPacket>).value.dataId, 0x27);
      final second = assembler.add(spo2.sublist(4));
      expect(second, Parsed(BigDataPacket(0x2A, const [0, 97, 99])));
    });

    test('a first byte other than 0xBC is rejected', () {
      expect(
        BigDataAssembler().add(const [0x27, 0, 0, 0, 0, 0]),
        const ParseFailure<BigDataPacket>(
          UnexpectedCommand(expected: 0xBC, actual: 0x27),
        ),
      );
    });

    test('a crc mismatch is reported with both values', () {
      final bad = [...sleep]..[4] ^= 0x01;
      final expected = crc16Modbus(List.generate(40, (i) => i));
      expect(
        BigDataAssembler().add(bad),
        ParseFailure<BigDataPacket>(
          ChecksumMismatch(expected: expected, actual: expected ^ 0x01),
        ),
      );
    });

    test('crc checking can be turned off until Phase 1 confirms it', () {
      final bad = [...sleep]..[4] ^= 0x01;
      expect(
        BigDataAssembler(verifyCrc: false).add(bad),
        isA<Parsed<BigDataPacket>>(),
      );
    });

    test('a byte outside 0..255 is out of range', () {
      expect(
        BigDataAssembler().add(const [0xBC, 0x1FF]),
        const ParseFailure<BigDataPacket>(
          ByteOutOfRange(index: 1, value: 0x1FF),
        ),
      );
    });
  });
}
