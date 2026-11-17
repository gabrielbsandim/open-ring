import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/domain/exif.dart';

import '../jpeg_fixture.dart';

final _wall = DateTime.utc(2026, 12, 10, 19, 32, 5);

Object? _fields(ExifTime? time) => time == null
    ? null
    : (time.wallClock, time.wallClock.isUtc, time.offsetMinutes);

void main() {
  group(
    'criterion 1: exifCaptureTime reads DateTimeOriginal and its offset',
    () {
      for (final order in [Endian.little, Endian.big]) {
        final name = order == Endian.little ? 'II' : 'MM';

        test('$name order gives wall clock 19:32:05 and offset -180', () {
          final time = exifCaptureTime(photoJpeg(exif: exifApp1(order: order)));

          expect(_fields(time), (_wall, true, -180));
        });

        test('$name order without OffsetTimeOriginal gives a null offset', () {
          final time = exifCaptureTime(
            photoJpeg(exif: exifApp1(order: order, offsetTimeOriginal: null)),
          );

          expect(_fields(time), (_wall, true, null));
        });
      }

      test('a positive half hour offset reads as +330', () {
        final time = exifCaptureTime(
          photoJpeg(exif: exifApp1(offsetTimeOriginal: '+05:30')),
        );

        expect(time?.offsetMinutes, 330);
      });

      test('an APP1 that is not the first segment is still found', () {
        final time = exifCaptureTime(
          bytesOf([
            soi,
            app0,
            xmpApp1,
            app2Icc,
            exifApp1(),
            dqt,
            sos,
            scan,
            eoi,
          ]),
        );

        expect(_fields(time), (_wall, true, -180));
      });
    },
  );

  group('criterion 1: no usable capture time gives null', () {
    test('a zero date', () {
      final bytes = photoJpeg(
        exif: exifApp1(dateTimeOriginal: '0000:00:00 00:00:00'),
      );

      expect(exifCaptureTime(bytes), isNull);
    });

    test('a blank date', () {
      final bytes = photoJpeg(
        exif: exifApp1(dateTimeOriginal: '    :  :     :  :  '),
      );

      expect(exifCaptureTime(bytes), isNull);
    });

    test('no APP1 at all', () {
      expect(exifCaptureTime(strippedPlain()), isNull);
    });

    test('only the XMP APP1', () {
      expect(
        exifCaptureTime(bytesOf([soi, xmpApp1, dqt, sos, scan, eoi])),
        isNull,
      );
    });

    test('only IFD0 DateTime (0x0132), which D2 does not read', () {
      final bytes = photoJpeg(
        exif: exifApp1(
          dateTimeOriginal: null,
          offsetTimeOriginal: null,
          dateTime: '2026:12:10 19:32:05',
        ),
      );

      expect(exifCaptureTime(bytes), isNull);
    });

    test('empty input', () {
      expect(exifCaptureTime(Uint8List(0)), isNull);
    });

    test('PNG and HEIC input', () {
      expect(exifCaptureTime(Uint8List.fromList(pngBytes)), isNull);
      expect(exifCaptureTime(Uint8List.fromList(heicBytes)), isNull);
    });
  });

  group('criterion 1: truncation and corruption never throw', () {
    final full = photoJpeg();
    final app1End = soi.length + app0.length + exifApp1().length;

    test('every prefix that cuts the Exif APP1 gives null', () {
      for (var length = 0; length < app1End; length++) {
        final prefix = Uint8List.sublistView(full, 0, length);

        expect(
          () => exifCaptureTime(prefix),
          returnsNormally,
          reason: 'prefix of $length bytes',
        );
        expect(exifCaptureTime(prefix), isNull, reason: 'prefix of $length');
      }
    });

    test('every longer prefix returns without throwing', () {
      for (var length = app1End; length <= full.length; length++) {
        expect(
          () => exifCaptureTime(Uint8List.sublistView(full, 0, length)),
          returnsNormally,
          reason: 'prefix of $length bytes',
        );
      }
    });

    test('an APP1 length past the end of the buffer gives null', () {
      final app1 = exifApp1();
      final bytes = bytesOf([soi, app0, app1]);
      final at = soi.length + app0.length;
      bytes[at + 2] = 0xFF;
      bytes[at + 3] = 0xF0;

      expect(() => exifCaptureTime(bytes), returnsNormally);
      expect(exifCaptureTime(bytes), isNull);
    });

    test('any single corrupted byte inside the APP1 never throws', () {
      final start = soi.length + app0.length;
      for (var i = start; i < app1End; i++) {
        for (final value in [0x00, 0xFF]) {
          final bytes = Uint8List.fromList(full)..[i] = value;

          expect(
            () => exifCaptureTime(bytes),
            returnsNormally,
            reason: 'byte $i set to $value',
          );
        }
      }
    });
  });
}
