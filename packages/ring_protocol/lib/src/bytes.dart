import 'package:ring_protocol/src/v1/frame.dart';

List<int> frameBytes(V1Frame frame) => [frame.command, ...frame.payload];

int uint16le(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int int16le(List<int> bytes, int offset) {
  final value = uint16le(bytes, offset);
  if (value < 0x8000) return value;
  return value - 0x10000;
}

int uint32le(List<int> bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

int uint24be(List<int> bytes, int offset) =>
    (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];

int uint16be(List<int> bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

int uint24le(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);

List<int> leUint16(int value) => [value & 0xFF, (value >> 8) & 0xFF];

List<int> leUint32(int value) => [
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

int toBcd(int value) {
  if (value < 0 || value > 99) {
    throw ArgumentError.value(value, 'value', 'BCD needs 0..99');
  }
  return ((value ~/ 10) << 4) | (value % 10);
}

int? fromBcd(int byte) {
  final tens = byte >> 4;
  final ones = byte & 0x0F;
  if (tens > 9 || ones > 9) return null;
  return tens * 10 + ones;
}

void checkByte(int value, String name) {
  if (value >= 0 && value <= 0xFF) return;
  throw ArgumentError.value(value, name, 'must fit in one byte');
}

int? firstOutOfRange(List<int> bytes) {
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] < 0 || bytes[i] > 0xFF) return i;
  }
  return null;
}

bool listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
