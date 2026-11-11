import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:ring_protocol/src/bytes.dart';
import 'package:ring_protocol/src/parse_result.dart';

int crc16Modbus(List<int> bytes) {
  var crc = 0xFFFF;
  for (final b in bytes) {
    crc ^= b & 0xFF;
    for (var i = 0; i < 8; i++) {
      final carry = crc & 1;
      crc >>= 1;
      if (carry != 0) crc ^= 0xA001;
    }
  }
  return crc & 0xFFFF;
}

abstract final class BigDataFrame {
  static const magic = 0xBC;
  static const headerLength = 6;
  // Gadgetbridge sends one 0xFF byte; Puxtril sends no payload (length 0,
  // crc 0xFFFF). Both are this encoder with a different payload.
  static const gadgetbridgeRequestPayload = [0xFF];
  static const puxtrilRequestPayload = <int>[];
}

Uint8List bigDataRequest(
  int dataId, [
  List<int> payload = BigDataFrame.gadgetbridgeRequestPayload,
]) {
  checkByte(dataId, 'dataId');
  for (final b in payload) {
    checkByte(b, 'payload');
  }
  if (payload.length > 0xFFFF) {
    throw ArgumentError.value(payload.length, 'payload', 'at most 65535');
  }
  return Uint8List.fromList([
    BigDataFrame.magic,
    dataId,
    ...leUint16(payload.length),
    ...leUint16(crc16Modbus(payload)),
    ...payload,
  ]);
}

@immutable
final class BigDataPacket {
  new(this.dataId, List<int> payload) : payload = List.unmodifiable(payload);

  final int dataId;
  final List<int> payload;

  @override
  bool operator ==(Object other) =>
      other is BigDataPacket &&
      other.dataId == dataId &&
      listEquals(other.payload, payload);

  @override
  int get hashCode => Object.hash(dataId, Object.hashAll(payload));

  @override
  String toString() =>
      'BigDataPacket(0x${dataId.toRadixString(16)}, ${payload.length} bytes)';
}

final class BigDataAssembler {
  new({this.verifyCrc = true});

  final bool verifyCrc;
  final _buffer = <int>[];

  bool get inProgress => _buffer.isNotEmpty;

  ParseResult<BigDataPacket>? add(List<int> chunk) {
    final outOfRange = firstOutOfRange(chunk);
    if (outOfRange != null) {
      return _fail(
        ByteOutOfRange(
          index: _buffer.length + outOfRange,
          value: chunk[outOfRange],
        ),
      );
    }
    _buffer.addAll(chunk);
    if (_buffer.isEmpty) return null;
    if (_buffer.first != BigDataFrame.magic) {
      return _fail(
        UnexpectedCommand(expected: BigDataFrame.magic, actual: _buffer.first),
      );
    }
    if (_buffer.length < BigDataFrame.headerLength) return null;
    final end = BigDataFrame.headerLength + uint16le(_buffer, 2);
    if (_buffer.length < end) return null;
    final dataId = _buffer[1];
    final crc = uint16le(_buffer, 4);
    final payload = _buffer.sublist(BigDataFrame.headerLength, end);
    _buffer.removeRange(0, end);
    final expected = crc16Modbus(payload);
    if (verifyCrc && crc != expected) {
      return ParseFailure(ChecksumMismatch(expected: expected, actual: crc));
    }
    return Parsed(BigDataPacket(dataId, payload));
  }

  void reset() => _buffer.clear();

  ParseResult<BigDataPacket> _fail(ParseError error) {
    reset();
    return ParseFailure(error);
  }
}

ParseError? bigDataIdError(BigDataPacket packet, int expected) {
  if (packet.dataId == expected) return null;
  return UnexpectedCommand(expected: expected, actual: packet.dataId);
}
