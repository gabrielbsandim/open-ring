import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

const codec = V1FrameCodec();

List<int> hex(String text) => [
  for (final byte in text.trim().split(RegExp(r'\s+')))
    int.parse(byte, radix: 16),
];

List<int> padded(List<int> head) {
  final body = [...head, ...List.filled(15 - head.length, 0)];
  return [...body, const MaskedSumChecksum().compute(body)];
}

V1Frame frame(List<int> bytes) {
  final raw = bytes.length == V1Frame.length ? bytes : padded(bytes);
  return switch (codec.decode(raw)) {
    Parsed(:final value) => value,
    ParseFailure(:final error) => throw StateError('bad fixture: $error'),
  };
}

Matcher parsed(Object? value) =>
    isA<Parsed<Object?>>().having((result) => result.value, 'value', value);

void sharedFailures<T>(
  int command,
  ParseResult<T> Function(V1Frame frame) parser,
) {
  final other = command == 0x03 ? 0x48 : 0x03;

  test('a truncated frame fails before the parser runs', () {
    expect(
      codec.parse(padded([command]).sublist(0, 10), parser),
      ParseFailure<T>(const WrongLength(expected: 16, actual: 10)),
    );
  });

  test('a frame for another command is rejected', () {
    expect(
      parser(frame([other, 80, 1])),
      ParseFailure<T>(UnexpectedCommand(expected: command, actual: other)),
    );
  });

  test('bit 7 on the command id reads as an error response', () {
    expect(
      parser(frame([command | V1Frame.errorBit])),
      ParseFailure<T>(ErrorResponse(command | V1Frame.errorBit)),
    );
  });
}
