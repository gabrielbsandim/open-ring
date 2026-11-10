import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/checksum.dart';
import 'package:ring_protocol/src/v1/command.dart';

@immutable
final class V1Frame {
  new _(this.command, Uint8List payload)
    : payload = payload.asUnmodifiableView();

  static const length = 16;
  static const payloadLength = 14;
  static const errorBit = 0x80;

  final int command;
  final Uint8List payload;

  @override
  bool operator ==(Object other) {
    if (other is! V1Frame || other.command != command) return false;
    for (var i = 0; i < payloadLength; i++) {
      if (other.payload[i] != payload[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(command, Object.hashAll(payload));

  @override
  String toString() => 'V1Frame(0x${command.toRadixString(16)}, $payload)';
}

final class V1FrameCodec {
  const new({this.checksum = const MaskedSumChecksum()});

  final ChecksumStrategy checksum;

  Uint8List encode(V1Command command, [List<int> payload = const []]) =>
      encodeRaw(command.id, payload);

  Uint8List encodeRaw(int command, [List<int> payload = const []]) {
    _checkByte(command, 'command');
    if (payload.length > V1Frame.payloadLength) {
      throw ArgumentError.value(
        payload.length,
        'payload',
        'at most ${V1Frame.payloadLength} bytes',
      );
    }
    for (final b in payload) {
      _checkByte(b, 'payload');
    }
    final bytes = Uint8List(V1Frame.length)
      ..[0] = command
      ..setRange(1, 1 + payload.length, payload);
    bytes[V1Frame.length - 1] = checksum.compute(_body(bytes));
    return bytes;
  }

  ParseResult<V1Frame> decode(List<int> bytes) {
    if (bytes.length != V1Frame.length) {
      return ParseFailure(
        WrongLength(expected: V1Frame.length, actual: bytes.length),
      );
    }
    final outOfRange = _firstOutOfRange(bytes);
    if (outOfRange != null) return ParseFailure(outOfRange);
    final expected = checksum.compute(_body(bytes));
    final actual = bytes[V1Frame.length - 1];
    if (actual != expected) {
      return ParseFailure(ChecksumMismatch(expected: expected, actual: actual));
    }
    return Parsed(
      V1Frame._(bytes[0], Uint8List.fromList(bytes.sublist(1, 15))),
    );
  }

  ParseResult<V1Frame> decodeResponse(List<int> bytes, V1Command request) {
    final result = decode(bytes);
    if (result is! Parsed<V1Frame>) return result;
    final command = result.value.command;
    if (command == request.id) return result;
    final flagged = request.id | V1Frame.errorBit;
    if (request.id != flagged && command == flagged) {
      return ParseFailure(ErrorResponse(command));
    }
    return ParseFailure(
      UnexpectedCommand(expected: request.id, actual: command),
    );
  }

  static List<int> _body(List<int> bytes) =>
      bytes.sublist(0, V1Frame.length - 1);

  static ByteOutOfRange? _firstOutOfRange(List<int> bytes) {
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] < 0 || bytes[i] > 0xFF) {
        return ByteOutOfRange(index: i, value: bytes[i]);
      }
    }
    return null;
  }

  static void _checkByte(int value, String name) {
    if (value >= 0 && value <= 0xFF) return;
    throw ArgumentError.value(value, name, 'must fit in one byte');
  }
}
