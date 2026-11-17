import 'dart:typed_data';

const _app0 = 0xE0;
const _app1 = 0xE1;
const _app2 = 0xE2;
const _app14 = 0xEE;
const _sos = 0xDA;
const _eoi = 0xD9;
const _orientationTag = 0x0112;
const _exifPointerTag = 0x8769;
const _dateTimeOriginalTag = 0x9003;
const _offsetTimeOriginalTag = 0x9011;

final _exifDate = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$');
final _exifOffset = RegExp(r'^([+-])(\d{2}):(\d{2})$');

final class ExifTime {
  const new({required this.wallClock, this.offsetMinutes});

  /// The capture wall clock, as a UTC flagged DateTime whose fields are local.
  final DateTime wallClock;

  /// Null when the photo does not say its offset.
  final int? offsetMinutes;
}

/// DateTimeOriginal and OffsetTimeOriginal of the first Exif APP1, or null
/// when there is no usable date; never throws.
ExifTime? exifCaptureTime(Uint8List bytes) {
  for (final (marker, start, end) in _headerSegments(bytes)) {
    if (marker != _app1) continue;
    final tiff = _Tiff.inApp1(bytes, start, end);
    if (tiff == null) continue;
    return _captureTime(tiff);
  }
  return null;
}

/// Drops every APPn but APP0, APP2 and APP14, every COM and anything after
/// the first EOI; a rotated photo gets back a minimal Orientation APP1.
Uint8List stripExif(Uint8List bytes) {
  if (!_isJpeg(bytes)) throw const FormatException('Not a JPEG.');
  final kept = <Uint8List>[];
  int? orientation;
  var at = 2;
  while (true) {
    if (at + 2 > bytes.length || bytes[at] != 0xFF) {
      throw FormatException('No marker where one belongs.', bytes, at);
    }
    final marker = bytes[at + 1];
    if (marker == 0xFF) {
      at++;
      continue;
    }
    if (marker == _eoi) break;
    final end = _segmentEnd(bytes, at);
    if (end == null) throw FormatException('A cut segment.', bytes, at);
    orientation ??= marker == _app1 ? _orientation(bytes, at, end) : null;
    final next = marker == _sos ? _scanEnd(bytes, end) : end;
    if (_keeps(marker)) kept.add(Uint8List.sublistView(bytes, at, next));
    at = next;
  }
  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  final afterApp0 = kept.isNotEmpty && kept.first[1] == _app0 ? 1 : 0;
  kept.take(afterApp0).forEach(out.add);
  if (orientation != null) out.add(_orientationApp1(orientation));
  kept.skip(afterApp0).forEach(out.add);
  out.add(const [0xFF, _eoi]);
  return out.takeBytes();
}

bool _isJpeg(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

bool _keeps(int marker) {
  if (marker == 0xFE) return false;
  if (marker < _app0 || marker > 0xEF) return true;
  return marker == _app0 || marker == _app2 || marker == _app14;
}

int? _segmentEnd(Uint8List bytes, int at) {
  if (at + 4 > bytes.length) return null;
  final length = bytes[at + 2] << 8 | bytes[at + 3];
  final end = at + 2 + length;
  if (length < 2 || end > bytes.length) return null;
  return end;
}

// Inside a scan only stuffed zeros, restart markers and fill bytes follow
// 0xFF; any other marker ends it.
int _scanEnd(Uint8List bytes, int from) {
  var at = from;
  while (at + 1 < bytes.length) {
    final next = bytes[at + 1];
    final continues =
        next == 0x00 || next == 0xFF || (next >= 0xD0 && next <= 0xD7);
    if (bytes[at] != 0xFF || continues) {
      at++;
      continue;
    }
    return at;
  }
  throw FormatException('A scan with no end.', bytes, from);
}

Iterable<(int, int, int)> _headerSegments(Uint8List bytes) sync* {
  if (!_isJpeg(bytes)) return;
  var at = 2;
  while (at + 1 < bytes.length && bytes[at] == 0xFF) {
    final marker = bytes[at + 1];
    if (marker == _sos || marker == _eoi) return;
    final end = _segmentEnd(bytes, at);
    if (end == null) return;
    yield (marker, at, end);
    at = end;
  }
}

int? _orientation(Uint8List bytes, int start, int end) {
  final tiff = _Tiff.inApp1(bytes, start, end);
  final value = tiff?.short(tiff.firstIfd, _orientationTag);
  if (value == null || value < 2 || value > 8) return null;
  return value;
}

Uint8List _orientationApp1(int value) => Uint8List.fromList([
  0xFF, 0xE1, 0x00, 0x22, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00, //
  0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00,
  0x01, 0x00,
  0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, value, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
]);

ExifTime? _captureTime(_Tiff tiff) {
  final exifIfd = tiff.long(tiff.firstIfd, _exifPointerTag);
  if (exifIfd == null) return null;
  final wall = _parseDate(tiff.ascii(exifIfd, _dateTimeOriginalTag));
  if (wall == null) return null;
  return ExifTime(
    wallClock: wall,
    offsetMinutes: _parseOffset(tiff.ascii(exifIfd, _offsetTimeOriginalTag)),
  );
}

DateTime? _parseDate(String? text) {
  final match = _exifDate.firstMatch(text ?? '');
  if (match == null) return null;
  final [year, month, day, hour, minute, second] = [
    for (var i = 1; i <= 6; i++) int.parse(match.group(i)!),
  ];
  final wall = DateTime.utc(year, month, day, hour, minute, second);
  final exact =
      (wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second) ==
      (year, month, day, hour, minute, second);
  return year > 0 && exact ? wall : null;
}

int? _parseOffset(String? text) {
  final match = _exifOffset.firstMatch(text ?? '');
  if (match == null) return null;
  final hours = int.parse(match.group(2)!);
  final minutes = int.parse(match.group(3)!);
  if (hours > 14 || minutes > 59) return null;
  final sign = match.group(1) == '-' ? -1 : 1;
  return sign * (hours * 60 + minutes);
}

/// Bounds checked reads over the TIFF body of an Exif APP1.
final class _Tiff {
  new(this._data, this._order);

  static _Tiff? inApp1(Uint8List bytes, int start, int end) {
    final body = start + 10;
    if (end < body + 8) return null;
    const exif = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
    for (var i = 0; i < exif.length; i++) {
      if (bytes[start + 4 + i] != exif[i]) return null;
    }
    final data = ByteData.sublistView(bytes, body, end);
    final order = switch ((bytes[body], bytes[body + 1])) {
      (0x49, 0x49) => Endian.little,
      (0x4D, 0x4D) => Endian.big,
      _ => null,
    };
    if (order == null || data.getUint16(2, order) != 42) return null;
    return _Tiff(data, order);
  }

  final ByteData _data;
  final Endian _order;

  int get firstIfd => _u32(4) ?? -1;

  int? short(int ifd, int tag) {
    final entry = _entry(ifd, tag);
    if (entry == null || _u16(entry + 2) != 3) return null;
    return _u16(entry + 8);
  }

  int? long(int ifd, int tag) {
    final entry = _entry(ifd, tag);
    if (entry == null || _u16(entry + 2) != 4) return null;
    return _u32(entry + 8);
  }

  String? ascii(int ifd, int tag) {
    final entry = _entry(ifd, tag);
    if (entry == null || _u16(entry + 2) != 2) return null;
    final count = _u32(entry + 4) ?? 0;
    final at = count <= 4 ? entry + 8 : _u32(entry + 8) ?? -1;
    if (count == 0 || at < 0 || at + count > _data.lengthInBytes) return null;
    final chars = [for (var i = 0; i < count; i++) _data.getUint8(at + i)]
        .takeWhile((char) => char != 0);
    return String.fromCharCodes(chars);
  }

  int? _entry(int ifd, int tag) {
    final count = _u16(ifd);
    if (count == null) return null;
    for (var i = 0; i < count; i++) {
      final at = ifd + 2 + 12 * i;
      final found = _u16(at);
      if (found == null) return null;
      if (found == tag) return at;
    }
    return null;
  }

  int? _u16(int at) => at >= 0 && at + 2 <= _data.lengthInBytes
      ? _data.getUint16(at, _order)
      : null;

  int? _u32(int at) => at >= 0 && at + 4 <= _data.lengthInBytes
      ? _data.getUint32(at, _order)
      : null;
}
