import 'dart:io';
import 'dart:typed_data';

// Play rejects screenshots with an alpha channel, and dart:ui only encodes
// RGBA, so the opaque capture is re-encoded as 8-bit RGB.
Uint8List encodeRgbPng(
  ByteData rgba, {
  required int width,
  required int height,
}) {
  final rows = Uint8List(height * (1 + width * 3));
  var target = 0;
  for (var y = 0; y < height; y++) {
    rows[target++] = 0;
    for (var x = 0; x < width; x++) {
      final source = (y * width + x) * 4;
      rows[target++] = rgba.getUint8(source);
      rows[target++] = rgba.getUint8(source + 1);
      rows[target++] = rgba.getUint8(source + 2);
    }
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  return (BytesBuilder(copy: false)
        ..add(const [137, 80, 78, 71, 13, 10, 26, 10])
        ..add(_chunk('IHDR', header.buffer.asUint8List()))
        ..add(_chunk('IDAT', ZLibCodec(level: 9).encode(rows)))
        ..add(_chunk('IEND', const [])))
      .takeBytes();
}

Uint8List _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32(body));
  return Uint8List.fromList([
    ...length.buffer.asUint8List(),
    ...body,
    ...crc.buffer.asUint8List(),
  ]);
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c.isOdd ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final byte in bytes) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
