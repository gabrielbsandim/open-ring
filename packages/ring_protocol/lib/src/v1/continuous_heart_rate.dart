import 'dart:typed_data';

import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v1/frame.dart';
import 'package:ring_protocol/src/v1/response.dart';

const continuousHeartRateTimeout = Duration(seconds: 60);

enum ContinuousHeartRateAction {
  enable(1),
  disable(2),
  keepAlive(3);

  new(this.id);

  final int id;
}

Uint8List continuousHeartRateRequest(
  ContinuousHeartRateAction action, {
  V1FrameCodec codec = const V1FrameCodec(),
}) => codec.encode(V1Command.continuousHeartRate, [action.id]);

ParseResult<int> parseContinuousHeartRate(V1Frame frame) {
  final error = commandError(frame, V1Command.continuousHeartRate.id);
  if (error != null) return ParseFailure(error);
  return Parsed(frame.payload[0]);
}
