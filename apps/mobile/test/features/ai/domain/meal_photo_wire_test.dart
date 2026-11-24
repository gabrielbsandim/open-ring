import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:open_ring/features/ai/domain/meal_photo_wire.dart';

import '../../food/jpeg_fixture.dart';
import '../wire_jpeg_fixture.dart';

void main() {
  group('prepareWirePhoto on the real encoder', () {
    test('the fixture really carries every leak before the wire step', () {
      final input = leakyPhoto(orientation: 6);
      final markers = headerMarkers(input);
      expect(markers, containsAll([0xE1, 0xE2, 0xED, 0xFE]));
      for (final secret in ['Exif', 'GPS', 'XMPSECRET', cameraSecret]) {
        expect(containsAscii(input, secret), isTrue, reason: secret);
      }
    });

    test('strips APP1, APP13, COM and every metadata string', () {
      final wire = prepareWirePhoto(leakyPhoto(orientation: 6));

      expectNoMetadata(wire.bytes);
    });

    test('bakes orientation 6 into the pixels and fits the long edge', () {
      final wire = prepareWirePhoto(leakyPhoto(orientation: 6));

      expect((wire.width, wire.height), (450, 768));
      final decoded = img.decodeJpg(wire.bytes)!;
      expect((decoded.width, decoded.height), (450, 768));
      // Rotating 90 degrees clockwise moves the red left half to the top.
      expect(decoded.getPixel(225, 100).r, greaterThan(200));
      expect(decoded.getPixel(225, 668).b, greaterThan(200));
      expect(wire.shortEdge, 450);
    });

    test('never upscales a photo already under 768 px', () {
      final wire = prepareWirePhoto(leakyPhoto(width: 600, height: 400));

      expect((wire.width, wire.height), (600, 400));
      expectNoMetadata(wire.bytes);
    });

    test('a portrait photo fits its height', () {
      final wire = prepareWirePhoto(leakyPhoto(width: 600, height: 1024));

      expect((wire.width, wire.height), (450, 768));
    });

    test('sha256 is the hex digest of the bytes sent', () {
      final wire = prepareWirePhoto(leakyPhoto(orientation: 6));

      expect(wire.sha256, sha256.convert(wire.bytes).toString());
      expect(wire.sha256, hasLength(64));
    });

    test('a non JPEG input throws FormatException', () {
      expect(
        () => prepareWirePhoto(Uint8List.fromList(pngBytes)),
        throwsFormatException,
      );
    });
  });
}
