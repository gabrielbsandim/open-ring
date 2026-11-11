import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:ring_protocol/src/bytes.dart';
import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v1/frame.dart';
import 'package:ring_protocol/src/v1/response.dart';

abstract final class V1ExtraCommandId {
  static const stopRealTime = 0x6A;
}

enum RealTimeType {
  heartRate(1),
  bloodPressure(2),
  spo2(3),
  fatigue(4),
  healthCheck(5),
  realTimeHeartRate(6),
  ecg(7),
  pressure(8),
  bloodSugar(9),
  hrv(10);

  new(this.id);

  final int id;

  static RealTimeType? fromId(int id) {
    for (final type in values) {
      if (type.id == id) return type;
    }
    return null;
  }
}

enum RealTimeAction {
  start(1),
  pause(2),
  resume(3),
  stop(4);

  new(this.id);

  final int id;
}

Uint8List realTimeRequest(
  RealTimeType type,
  RealTimeAction action, {
  V1FrameCodec codec = const V1FrameCodec(),
}) => codec.encode(V1Command.realTimeData, [type.id, action.id]);

Uint8List realTimeStopRequest(
  RealTimeType type, {
  V1FrameCodec codec = const V1FrameCodec(),
}) => codec.encodeRaw(V1ExtraCommandId.stopRealTime, [type.id, 0, 0]);

@immutable
final class RealTimeReading {
  const new({required this.type, required this.errorCode, required this.value});

  final RealTimeType type;
  final int errorCode;
  final int value;

  bool get isError => errorCode != 0;

  @override
  bool operator ==(Object other) =>
      other is RealTimeReading &&
      other.type == type &&
      other.errorCode == errorCode &&
      other.value == value;

  @override
  int get hashCode => Object.hash(type, errorCode, value);
}

ParseResult<RealTimeReading> parseRealTimeReading(V1Frame frame) {
  final error = commandError(frame, V1Command.realTimeData.id);
  if (error != null) return ParseFailure(error);
  final b = frameBytes(frame);
  final type = RealTimeType.fromId(b[1]);
  if (type == null) return ParseFailure(ByteOutOfRange(index: 1, value: b[1]));
  return Parsed(RealTimeReading(type: type, errorCode: b[2], value: b[3]));
}

ParseResult<V1Frame> parseRealTimeStop(V1Frame frame) {
  final error = commandError(frame, V1ExtraCommandId.stopRealTime);
  if (error != null) return ParseFailure(error);
  return Parsed(frame);
}
