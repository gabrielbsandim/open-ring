import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

List<int> frame(List<int> head, int checksum) => [
  ...head,
  ...List.filled(15 - head.length, 0),
  checksum,
];

void main() {
  const codec = V1FrameCodec();

  group('encode', () {
    test('battery request is the id, zero padding and the id as checksum', () {
      expect(codec.encode(V1Command.battery), frame([0x03], 0x03));
    });

    test('find device carries 0x55 0xAA and masks the sum to one byte', () {
      expect(
        codec.encode(V1Command.findDevice, [0x55, 0xAA]),
        frame([0x50, 0x55, 0xAA], 0x4F),
      );
    });

    test('a full 14 byte payload fills bytes 1 to 14', () {
      final payload = List.generate(14, (i) => i + 1);
      final bytes = codec.encodeRaw(0x01, payload);
      expect(bytes.length, 16);
      expect(bytes.sublist(1, 15), payload);
      expect(bytes[15], (0x01 + 105) & 0xFF);
    });

    test('rejects a payload longer than 14 bytes', () {
      expect(
        () => codec.encodeRaw(0x01, List.filled(15, 0)),
        throwsArgumentError,
      );
    });

    test('rejects a command or payload byte outside 0..255', () {
      expect(() => codec.encodeRaw(0x100), throwsArgumentError);
      expect(() => codec.encodeRaw(0x01, [-1]), throwsArgumentError);
    });
  });

  group('decode', () {
    test('parses a battery response', () {
      final result = codec.decode(frame([0x03, 0x50, 0x01], 0x54));
      final parsed = result as Parsed<V1Frame>;
      expect(parsed.value.command, 0x03);
      expect(parsed.value.payload.take(2), [0x50, 0x01]);
      expect(parsed.value.payload.length, 14);
    });

    test('round trips what encode builds', () {
      final bytes = codec.encode(V1Command.realTimeData, [6, 1]);
      final parsed = codec.decode(bytes) as Parsed<V1Frame>;
      expect(
        codec.encodeRaw(parsed.value.command, parsed.value.payload),
        bytes,
      );
    });

    test('reports a frame that is not 16 bytes', () {
      expect(
        codec.decode([0x03, 0x03]),
        const ParseFailure<V1Frame>(WrongLength(expected: 16, actual: 2)),
      );
    });

    test('reports a byte that does not fit in one byte', () {
      expect(
        codec.decode(frame([0x03, 0x1FF], 0x02)),
        const ParseFailure<V1Frame>(ByteOutOfRange(index: 1, value: 0x1FF)),
      );
    });

    test('reports a checksum mismatch with both values', () {
      expect(
        codec.decode(frame([0x03, 0x50, 0x01], 0x55)),
        const ParseFailure<V1Frame>(
          ChecksumMismatch(expected: 0x54, actual: 0x55),
        ),
      );
    });

    test('the payload of a parsed frame cannot be changed', () {
      final parsed = codec.decode(frame([0x03], 0x03)) as Parsed<V1Frame>;
      expect(() => parsed.value.payload[0] = 1, throwsUnsupportedError);
    });
  });

  group('decodeResponse', () {
    test('accepts the command that was asked for', () {
      final result = codec.decodeResponse(
        frame([0x03, 0x50], 0x53),
        V1Command.battery,
      );
      expect(result, isA<Parsed<V1Frame>>());
    });

    test('reads bit 7 on the requested id as an error response', () {
      expect(
        codec.decodeResponse(frame([0x83], 0x83), V1Command.battery),
        const ParseFailure<V1Frame>(ErrorResponse(0x83)),
      );
    });

    test('reports a response to a different command', () {
      expect(
        codec.decodeResponse(frame([0x15], 0x15), V1Command.battery),
        const ParseFailure<V1Frame>(
          UnexpectedCommand(expected: 0x03, actual: 0x15),
        ),
      );
    });

    test('a command with bit 7 already set never reads as an error', () {
      expect(
        codec.decodeResponse(frame([0xBC], 0xBC), V1Command.bigData),
        isA<Parsed<V1Frame>>(),
      );
    });
  });

  group('checksum strategy', () {
    test('masked sum and modulo 255 disagree once the sum passes 255', () {
      final body = frame([0x50, 0x55, 0xAA], 0).sublist(0, 15);
      expect(const MaskedSumChecksum().compute(body), 0x4F);
      expect(const Modulo255SumChecksum().compute(body), 0x50);
    });

    test('a codec built with modulo 255 validates against that rule', () {
      const modulo = V1FrameCodec(checksum: Modulo255SumChecksum());
      final bytes = frame([0x50, 0x55, 0xAA], 0x50);
      expect(modulo.decode(bytes), isA<Parsed<V1Frame>>());
      expect(codec.decode(bytes), isA<ParseFailure<V1Frame>>());
    });
  });
}
