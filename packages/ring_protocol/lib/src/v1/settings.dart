import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:ring_protocol/src/bytes.dart';
import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v1/frame.dart';
import 'package:ring_protocol/src/v1/response.dart';

@immutable
final class AutoHeartRateSetting {
  const new({required this.enabled, required this.intervalMinutes});

  final bool enabled;
  final int intervalMinutes;

  @override
  bool operator ==(Object other) =>
      other is AutoHeartRateSetting &&
      other.enabled == enabled &&
      other.intervalMinutes == intervalMinutes;

  @override
  int get hashCode => Object.hash(enabled, intervalMinutes);
}

enum AutoMonitor {
  spo2(V1Command.autoSpo2Setting),
  stress(V1Command.autoStressSetting),
  hrv(V1Command.autoHrvSetting);

  new(this.command);

  final V1Command command;
}

Uint8List autoHeartRateReadRequest({
  V1FrameCodec codec = const V1FrameCodec(),
}) => codec.encode(V1Command.autoHeartRateSetting, [SettingAction.read.id]);

Uint8List autoHeartRateWriteRequest(
  AutoHeartRateSetting setting, {
  V1FrameCodec codec = const V1FrameCodec(),
}) {
  checkByte(setting.intervalMinutes, 'intervalMinutes');
  return codec.encode(V1Command.autoHeartRateSetting, [
    SettingAction.write.id,
    if (setting.enabled) 1 else 2,
    setting.intervalMinutes,
  ]);
}

ParseResult<AutoHeartRateSetting> parseAutoHeartRateSetting(V1Frame frame) {
  final error = _readError(frame, V1Command.autoHeartRateSetting);
  if (error != null) return ParseFailure(error);
  final b = frameBytes(frame);
  final enabled = switch (b[2]) {
    1 => true,
    2 => false,
    _ => null,
  };
  if (enabled == null) {
    return ParseFailure(ByteOutOfRange(index: 2, value: b[2]));
  }
  return Parsed(AutoHeartRateSetting(enabled: enabled, intervalMinutes: b[3]));
}

Uint8List autoMonitorReadRequest(
  AutoMonitor monitor, {
  V1FrameCodec codec = const V1FrameCodec(),
}) => codec.encode(monitor.command, [SettingAction.read.id]);

Uint8List autoMonitorWriteRequest(
  AutoMonitor monitor, {
  required bool enabled,
  V1FrameCodec codec = const V1FrameCodec(),
}) => codec.encode(monitor.command, [
  SettingAction.write.id,
  if (enabled) 1 else 0,
]);

ParseResult<bool> parseAutoMonitor(V1Frame frame, AutoMonitor monitor) {
  final error = _readError(frame, monitor.command);
  if (error != null) return ParseFailure(error);
  final b = frameBytes(frame);
  return switch (b[2]) {
    1 => const Parsed(true),
    0 || 2 => const Parsed(false),
    _ => ParseFailure(ByteOutOfRange(index: 2, value: b[2])),
  };
}

ParseResult<SettingAction> parseSettingAck(V1Frame frame, V1Command command) {
  final error = commandError(frame, command.id);
  if (error != null) return ParseFailure(error);
  final action = frame.payload[0];
  for (final candidate in SettingAction.values) {
    if (candidate.id == action) return Parsed(candidate);
  }
  return ParseFailure(ByteOutOfRange(index: 1, value: action));
}

ParseError? _readError(V1Frame frame, V1Command command) {
  final error = commandError(frame, command.id);
  if (error != null) return error;
  final action = frame.payload[0];
  if (action == SettingAction.read.id) return null;
  return ByteOutOfRange(index: 1, value: action);
}
