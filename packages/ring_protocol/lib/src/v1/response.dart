import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v1/frame.dart';

ParseError? commandError(V1Frame frame, int expected) {
  if (frame.command == expected) return null;
  if (frame.command == (expected | V1Frame.errorBit)) {
    return ErrorResponse(frame.command);
  }
  return UnexpectedCommand(expected: expected, actual: frame.command);
}

ParseResult<V1Frame> parseAck(V1Frame frame, V1Command command) {
  final error = commandError(frame, command.id);
  if (error != null) return ParseFailure(error);
  return Parsed(frame);
}

extension V1Parse on V1FrameCodec {
  ParseResult<T> parse<T>(
    List<int> bytes,
    ParseResult<T> Function(V1Frame frame) parser,
  ) => switch (decode(bytes)) {
    Parsed(:final value) => parser(value),
    ParseFailure(:final error) => ParseFailure(error),
  };
}
