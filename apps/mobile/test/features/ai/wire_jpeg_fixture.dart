import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../food/jpeg_fixture.dart';

const String cameraSecret = 'CAMSECRETMODEL';

/// A real 1024 x 600 JPEG, left half red and right half blue, carrying an
/// Exif APP1 written by the encoder (Orientation 6 and a camera model) plus
/// spliced GPS Exif, XMP, ICC APP2, IPTC APP13 and COM segments.
Uint8List leakyPhoto({int width = 1024, int height = 600, int? orientation}) {
  final image = img.Image(width: width, height: height);
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: width ~/ 2 - 1,
    y2: height - 1,
    color: img.ColorRgb8(255, 0, 0),
  );
  img.fillRect(
    image,
    x1: width ~/ 2,
    y1: 0,
    x2: width - 1,
    y2: height - 1,
    color: img.ColorRgb8(0, 0, 255),
  );
  image.exif.imageIfd['Model'] = cameraSecret;
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  final encoded = img.encodeJpg(image, quality: 90);
  return bytesOf([
    soi,
    if (orientation != null) exifApp1(orientation: orientation),
    xmpApp1,
    app2Icc,
    app13,
    com,
    encoded.sublist(2),
  ]);
}

/// Marker codes of every segment before the first SOS.
List<int> headerMarkers(List<int> jpeg) {
  final markers = <int>[];
  var i = 2;
  while (i + 4 <= jpeg.length && jpeg[i] == 0xFF) {
    final marker = jpeg[i + 1];
    markers.add(marker);
    if (marker == 0xDA) break;
    i += 2 + (jpeg[i + 2] << 8 | jpeg[i + 3]);
  }
  return markers;
}

void expectNoMetadata(List<int> jpeg) {
  final markers = headerMarkers(jpeg);
  expect(markers, contains(0xDA), reason: 'walk reached the scan');
  expect(markers, isNot(contains(0xE1)), reason: 'APP1');
  expect(markers, isNot(contains(0xE2)), reason: 'APP2 ICC');
  expect(markers, isNot(contains(0xED)), reason: 'APP13');
  expect(markers, isNot(contains(0xFE)), reason: 'COM');
  for (final secret in [
    'Exif',
    'GPS',
    'XMPSECRET',
    'IPTCSECRET',
    'COMMENTSECRET',
    cameraSecret,
  ]) {
    expect(containsAscii(jpeg, secret), isFalse, reason: secret);
  }
}
