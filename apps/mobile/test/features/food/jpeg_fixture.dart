import 'dart:convert';
import 'dart:typed_data';

const soi = [0xFF, 0xD8];
const eoi = [0xFF, 0xD9];

List<int> segment(int marker, List<int> payload) {
  final length = payload.length + 2;
  return [0xFF, marker, length >> 8, length & 0xFF, ...payload];
}

final List<int> app0 = segment(0xE0, [
  ...ascii.encode('JFIF'),
  0,
  1,
  1,
  0,
  0,
  1,
  0,
  1,
  0,
  0,
]);

final List<int> xmpApp1 = segment(0xE1, [
  ...ascii.encode('http://ns.adobe.com/xap/1.0/'),
  0,
  ...ascii.encode('<x:xmpmeta>XMPSECRET</x:xmpmeta>'),
]);

final List<int> app2Icc = segment(0xE2, [
  ...ascii.encode('ICC_PROFILE'),
  0,
  1,
  1,
  0xAA,
  0xBB,
  0xCC,
  0xDD,
]);

final List<int> app13 = segment(0xED, [
  ...ascii.encode('Photoshop 3.0'),
  0,
  ...ascii.encode('8BIMIPTCSECRET'),
]);

final List<int> app14 = segment(0xEE, [
  ...ascii.encode('Adobe'),
  0,
  100,
  0,
  0,
  0,
  0,
  1,
]);

final List<int> com = segment(0xFE, ascii.encode('COMMENTSECRET'));

final List<int> dqt = segment(0xDB, [0x00, for (var i = 1; i <= 64; i++) i]);

final List<int> sof0 = segment(0xC0, [8, 0, 16, 0, 16, 1, 1, 0x11, 0]);

final List<int> dht = segment(0xC4, [
  0x00,
  0,
  1,
  for (var i = 0; i < 14; i++) 0,
  0x05,
]);

final List<int> sos = segment(0xDA, [1, 1, 0x00, 0, 63, 0]);

// Byte stuffing and a restart marker, so a stripper that parses the scan as
// segments breaks it.
const scan = [0x12, 0x34, 0xFF, 0x00, 0x56, 0xFF, 0xD0, 0x78, 0x9A, 0xFF, 0x00];

/// The gain map JPEG an Ultra HDR photo appends after the primary EOI.
final List<int> ultraHdrTrailer = [
  ...soi,
  ...segment(0xE1, [
    ...ascii.encode('http://ns.adobe.com/xap/1.0/'),
    0,
    ...ascii.encode('hdrgm:Version GAINMAPSECRET'),
  ]),
  ...dqt,
  ...eoi,
];

const gpsSecret = 'GPSSECRET';

const pngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13];

const heicBytes = [
  0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, //
  0x68, 0x65, 0x69, 0x63, 0x00, 0x00, 0x00, 0x00,
  0x6D, 0x69, 0x66, 0x31, 0x68, 0x65, 0x69, 0x63,
];

Uint8List bytesOf(List<List<int>> parts) =>
    Uint8List.fromList([for (final part in parts) ...part]);

int indexOfBytes(List<int> haystack, List<int> needle, [int start = 0]) {
  for (var i = start; i <= haystack.length - needle.length; i++) {
    var j = 0;
    while (j < needle.length && haystack[i + j] == needle[j]) {
      j++;
    }
    if (j == needle.length) return i;
  }
  return -1;
}

bool containsAscii(List<int> haystack, String text) =>
    indexOfBytes(haystack, ascii.encode(text)) >= 0;

String exifDate(DateTime wall) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${wall.year.toString().padLeft(4, '0')}:${two(wall.month)}:'
      '${two(wall.day)} ${two(wall.hour)}:${two(wall.minute)}:'
      '${two(wall.second)}';
}

final class _Entry {
  const new(this.tag, this.type, this.count, this.value);

  final int tag;
  final int type;
  final int count;
  final List<int> value;
}

const _byte = 1;
const _ascii = 2;
const _short = 3;
const _long = 4;
const _undefined = 7;

List<int> _u16(int v, Endian order) {
  final data = ByteData(2)..setUint16(0, v, order);
  return data.buffer.asUint8List();
}

List<int> _u32(int v, Endian order) {
  final data = ByteData(4)..setUint32(0, v, order);
  return data.buffer.asUint8List();
}

_Entry _asciiEntry(int tag, String text) {
  final value = [...ascii.encode(text), 0];
  return _Entry(tag, _ascii, value.length, value);
}

int _ifdSize(List<_Entry> entries) {
  var size = 2 + 12 * entries.length + 4;
  for (final entry in entries) {
    if (entry.value.length <= 4) continue;
    size += entry.value.length + entry.value.length % 2;
  }
  return size;
}

List<int> _ifd(List<_Entry> entries, int start, Endian order) {
  final head = <int>[..._u16(entries.length, order)];
  final data = <int>[];
  final dataStart = start + 2 + 12 * entries.length + 4;
  for (final entry in entries) {
    head
      ..addAll(_u16(entry.tag, order))
      ..addAll(_u16(entry.type, order))
      ..addAll(_u32(entry.count, order));
    if (entry.value.length <= 4) {
      head.addAll([...entry.value, ...List.filled(4 - entry.value.length, 0)]);
      continue;
    }
    head.addAll(_u32(dataStart + data.length, order));
    data.addAll(entry.value);
    if (entry.value.length.isOdd) data.add(0);
  }
  return [...head, ..._u32(0, order), ...data];
}

List<int> exifApp1({
  Endian order = Endian.little,
  int? orientation = 6,
  String? dateTimeOriginal = '2026:12:10 19:32:05',
  String? offsetTimeOriginal = '-03:00',
  String? dateTime,
  bool gps = true,
}) {
  final exif = <_Entry>[
    if (dateTimeOriginal != null) _asciiEntry(0x9003, dateTimeOriginal),
    if (offsetTimeOriginal != null) _asciiEntry(0x9011, offsetTimeOriginal),
  ];
  final gpsEntries = <_Entry>[
    const _Entry(0x0000, _byte, 4, [2, 2, 0, 0]),
    _asciiEntry(0x0001, 'S'),
    _Entry(0x001B, _undefined, 8 + gpsSecret.length, [
      ...ascii.encode('ASCII'),
      0,
      0,
      0,
      ...ascii.encode(gpsSecret),
    ]),
  ];
  List<_Entry> ifd0({required int exifAt, required int gpsAt}) => [
    if (orientation != null)
      _Entry(0x0112, _short, 1, _u16(orientation, order)),
    if (dateTime != null) _asciiEntry(0x0132, dateTime),
    if (exif.isNotEmpty) _Entry(0x8769, _long, 1, _u32(exifAt, order)),
    if (gps) _Entry(0x8825, _long, 1, _u32(gpsAt, order)),
  ];
  const ifd0At = 8;
  final exifAt = ifd0At + _ifdSize(ifd0(exifAt: 0, gpsAt: 0));
  final gpsAt = exifAt + (exif.isEmpty ? 0 : _ifdSize(exif));
  final tiff = [
    ...(order == Endian.little ? ascii.encode('II') : ascii.encode('MM')),
    ..._u16(42, order),
    ..._u32(ifd0At, order),
    ..._ifd(ifd0(exifAt: exifAt, gpsAt: gpsAt), ifd0At, order),
    if (exif.isNotEmpty) ..._ifd(exif, exifAt, order),
    if (gps) ..._ifd(gpsEntries, gpsAt, order),
  ];
  return segment(0xE1, [...ascii.encode('Exif'), 0, 0, ...tiff]);
}

Uint8List photoJpeg({List<int>? exif, bool trailer = true}) => bytesOf([
  soi,
  app0,
  exif ?? exifApp1(),
  xmpApp1,
  app2Icc,
  app13,
  app14,
  com,
  dqt,
  sof0,
  dht,
  sos,
  scan,
  eoi,
  if (trailer) ultraHdrTrailer,
]);

Uint8List strippedPlain() =>
    bytesOf([soi, app0, app2Icc, app14, dqt, sof0, dht, sos, scan, eoi]);

List<int> orientationApp1(Endian order, int value) => [
  0xFF, 0xE1, 0x00, 0x22, //
  0x45, 0x78, 0x69, 0x66, 0x00, 0x00,
  ...(order == Endian.little
      ? [0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00]
      : [0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08]),
  ..._u16(1, order),
  ..._u16(0x0112, order),
  ..._u16(3, order),
  ..._u32(1, order),
  ..._u16(value, order),
  0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
];
