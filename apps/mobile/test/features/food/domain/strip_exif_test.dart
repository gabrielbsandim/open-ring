import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/domain/exif.dart';

import '../jpeg_fixture.dart';

const _orientation6Ii = [
  0xFF, 0xE1, 0x00, 0x22, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00, //
  0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00,
  0x01, 0x00,
  0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
];

const _orientation6Mm = [
  0xFF, 0xE1, 0x00, 0x22, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00, //
  0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08,
  0x00, 0x01,
  0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x06, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
];

(Uint8List rest, int at, List<int> app1) _cutOrientation(
  Uint8List out,
  int value,
) {
  for (final order in [Endian.little, Endian.big]) {
    final app1 = orientationApp1(order, value);
    final at = indexOfBytes(out, app1);
    if (at < 0) continue;
    final rest = Uint8List.fromList([
      ...out.sublist(0, at),
      ...out.sublist(at + app1.length),
    ]);
    return (rest, at, app1);
  }
  throw TestFailure('no 36 byte Orientation $value APP1 in the output');
}

void main() {
  group('criterion 2: stripExif drops every metadata segment', () {
    final plain = strippedPlain();

    for (final order in [Endian.little, Endian.big]) {
      final name = order == Endian.little ? 'II' : 'MM';
      final input = photoJpeg(exif: exifApp1(order: order, orientation: 1));

      test('$name: no Exif or XMP APP1, no GPS, no COM, no APP13', () {
        final out = stripExif(input);

        expect(indexOfBytes(out, [0xFF, 0xE1]), -1, reason: 'an APP1 is left');
        expect(containsAscii(out, 'Exif'), isFalse);
        expect(containsAscii(out, gpsSecret), isFalse);
        expect(containsAscii(out, '2026:12:10'), isFalse);
        expect(containsAscii(out, 'XMPSECRET'), isFalse);
        expect(containsAscii(out, 'COMMENTSECRET'), isFalse);
        expect(containsAscii(out, 'Photoshop 3.0'), isFalse);
      });

      test('$name: nothing after the first EOI (Ultra HDR trailer)', () {
        final out = stripExif(input);

        expect(out.sublist(out.length - 2), eoi);
        expect(containsAscii(out, 'GAINMAPSECRET'), isFalse);
      });

      test('$name: the kept segments are byte identical and in order', () {
        expect(stripExif(input), plain);
      });
    }

    test('no Orientation writes no APP1', () {
      final input = photoJpeg(exif: exifApp1(orientation: null));

      expect(stripExif(input), plain);
    });

    test('Orientation 9 is not a valid value and writes no APP1', () {
      final input = photoJpeg(exif: exifApp1(orientation: 9));

      expect(stripExif(input), plain);
    });

    test('a JPEG with no metadata comes back unchanged', () {
      expect(stripExif(plain), plain);
    });
  });

  group('criterion 2: Orientation 6 is written back as 36 exact bytes', () {
    for (final order in [Endian.little, Endian.big]) {
      final name = order == Endian.little ? 'II' : 'MM';

      test('$name input', () {
        final out = stripExif(photoJpeg(exif: exifApp1(order: order)));
        final (rest, at, app1) = _cutOrientation(out, 6);

        expect(app1, anyOf(equals(_orientation6Ii), equals(_orientation6Mm)));
        expect(
          rest,
          strippedPlain(),
          reason: 'everything else is the plain strip',
        );
        expect(at, greaterThanOrEqualTo(soi.length));
        expect(
          at,
          lessThan(indexOfBytes(out, dqt)),
          reason: 'before the tables',
        );
        expect(containsAscii(out, gpsSecret), isFalse);
      });
    }

    test('an Exif APP1 right after SOI, with no APP0, keeps Orientation', () {
      final input = bytesOf([soi, exifApp1(), dqt, sof0, dht, sos, scan, eoi]);
      final (rest, _, _) = _cutOrientation(stripExif(input), 6);

      expect(rest, bytesOf([soi, dqt, sof0, dht, sos, scan, eoi]));
    });

    for (var value = 2; value <= 8; value++) {
      test('Orientation $value is kept with its value', () {
        final out = stripExif(photoJpeg(exif: exifApp1(orientation: value)));
        final (rest, _, _) = _cutOrientation(out, value);

        expect(rest, strippedPlain());
      });
    }
  });

  group('criterion 2: stripping twice equals stripping once', () {
    for (final orientation in [null, 1, 6, 8]) {
      for (final order in [Endian.little, Endian.big]) {
        test(
          'Orientation $orientation, ${order == Endian.little ? 'II' : 'MM'}',
          () {
            final once = stripExif(
              photoJpeg(
                exif: exifApp1(order: order, orientation: orientation),
              ),
            );

            expect(stripExif(once), once);
          },
        );
      }
    }
  });

  group('criterion 2: non JPEG input throws FormatException', () {
    test('PNG', () {
      expect(
        () => stripExif(Uint8List.fromList(pngBytes)),
        throwsFormatException,
      );
    });

    test('HEIC', () {
      expect(
        () => stripExif(Uint8List.fromList(heicBytes)),
        throwsFormatException,
      );
    });

    test('empty input', () {
      expect(() => stripExif(Uint8List(0)), throwsFormatException);
    });

    test('an APP1 length past the end of the buffer', () {
      final bytes = bytesOf([soi, app0, exifApp1()]);
      final at = soi.length + app0.length;
      bytes[at + 2] = 0xFF;
      bytes[at + 3] = 0xF0;

      expect(() => stripExif(bytes), throwsFormatException);
    });
  });
}
