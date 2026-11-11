import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/domain/hex_bytes.dart';
import 'package:open_ring/features/ring/domain/raw_frame.dart';

void main() {
  group('HexBytes', () {
    test('encodes lowercase, two digits per byte', () {
      expect(HexBytes.encode([0x03, 0x0A, 0xFF]), '030aff');
      expect(HexBytes.spaced([0x03, 0x0A, 0xFF]), '03 0a ff');
    });

    test('decodes with or without separators and in either case', () {
      expect(HexBytes.tryDecode('030AFF'), [0x03, 0x0A, 0xFF]);
      expect(HexBytes.tryDecode('03 0a ff'), [0x03, 0x0A, 0xFF]);
      expect(HexBytes.tryDecode('03:0a-ff,\n10'), [0x03, 0x0A, 0xFF, 0x10]);
      expect(HexBytes.tryDecode(''), isEmpty);
    });

    test('rejects odd lengths and non hex digits', () {
      expect(HexBytes.tryDecode('030'), isNull);
      expect(HexBytes.tryDecode('0x03'), isNull);
      expect(HexBytes.tryDecode('zz'), isNull);
    });

    test('round trips every byte value', () {
      final all = List.generate(256, (i) => i);
      expect(HexBytes.tryDecode(HexBytes.encode(all)), all);
    });
  });

  group('RawFrame.parse', () {
    const battery = '03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 03';

    test('accepts a 16 byte frame as typed, checksum untouched', () {
      final input = RawFrame.parse('${battery.substring(0, 45)}ff');

      expect(input, isA<ValidRawFrame>());
      final bytes = (input as ValidRawFrame).bytes;
      expect(bytes, hasLength(16));
      expect(bytes.first, 0x03);
      expect(bytes.last, 0xFF);
    });

    test('rejects blank input', () {
      expect(
        RawFrame.parse('   '),
        isA<InvalidRawFrame>().having(
          (e) => e.error,
          'error',
          RawFrameError.empty,
        ),
      );
    });

    test('rejects text that is not hex', () {
      expect(
        RawFrame.parse('03 00 zz'),
        isA<InvalidRawFrame>().having(
          (e) => e.error,
          'error',
          RawFrameError.notHex,
        ),
      );
    });

    test('rejects a frame of the wrong length and reports its size', () {
      expect(
        RawFrame.parse('03 00 03'),
        isA<InvalidRawFrame>()
            .having((e) => e.error, 'error', RawFrameError.wrongLength)
            .having((e) => e.byteCount, 'byteCount', 3),
      );
    });

    for (final command in ['08', 'ff', 'FF']) {
      test('blocks command 0x$command', () {
        expect(
          RawFrame.parse('$command${battery.substring(2)}'),
          isA<InvalidRawFrame>().having(
            (e) => e.error,
            'error',
            RawFrameError.blockedCommand,
          ),
        );
      });
    }
  });
}
