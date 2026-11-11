import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:ring_protocol/src/bytes.dart';
import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v1/frame.dart';
import 'package:ring_protocol/src/v1/response.dart';

Uint8List heartRateLogRequest(
  int wallClockSeconds, {
  V1FrameCodec codec = const V1FrameCodec(),
}) {
  if (wallClockSeconds < 0 || wallClockSeconds > 0xFFFFFFFF) {
    throw ArgumentError.value(wallClockSeconds, 'wallClockSeconds');
  }
  return codec.encode(V1Command.heartRateLog, leUint32(wallClockSeconds));
}

Uint8List stressLogRequest({
  int daysAgo = 0,
  V1FrameCodec codec = const V1FrameCodec(),
}) {
  checkByte(daysAgo, 'daysAgo');
  return codec.encode(V1Command.stressLog, [daysAgo]);
}

Uint8List hrvLogRequest({
  int daysAgo = 0,
  V1FrameCodec codec = const V1FrameCodec(),
}) {
  checkByte(daysAgo, 'daysAgo');
  return codec.encode(V1Command.hrvLog, [daysAgo]);
}

@immutable
final class SlotLog {
  new({
    required this.intervalMinutes,
    required List<int> values,
    this.reportedSeconds,
  }) : values = List.unmodifiable(values);

  final int intervalMinutes;
  final List<int> values;
  final int? reportedSeconds;

  @override
  bool operator ==(Object other) =>
      other is SlotLog &&
      other.intervalMinutes == intervalMinutes &&
      other.reportedSeconds == reportedSeconds &&
      listEquals(other.values, values);

  @override
  int get hashCode =>
      Object.hash(intervalMinutes, reportedSeconds, Object.hashAll(values));

  @override
  String toString() =>
      'SlotLog(every $intervalMinutes min, ${values.length} values)';
}

final class SlotLogAssembler {
  new _(this.command, this._firstDataOffset, this._defaultInterval);

  new heartRate() : this._(V1Command.heartRateLog, 6, 5);

  new stress() : this._(V1Command.stressLog, 3, 30);

  new hrv() : this._(V1Command.hrvLog, 3, 30);

  static const noData = 0xFF;

  final V1Command command;
  final int _firstDataOffset;
  final int _defaultInterval;

  int? _total;
  int _interval = 0;
  int _next = 1;
  int? _reportedSeconds;
  final _values = <int>[];

  bool get inProgress => _total != null;

  ParseResult<SlotLog>? add(V1Frame frame) {
    final error = commandError(frame, command.id);
    if (error != null) return _finish(ParseFailure(error));
    final b = frameBytes(frame);
    final index = b[1];
    if (index == noData) {
      return _finish(Parsed(SlotLog(intervalMinutes: 0, values: const [])));
    }
    if (index == 0) return _start(b);
    final total = _total;
    if (total == null || index != _next) {
      return _finish(ParseFailure(ByteOutOfRange(index: 1, value: index)));
    }
    if (index == 1 && command == V1Command.heartRateLog) {
      _reportedSeconds = uint32le(b, 2);
    }
    _values.addAll(b.sublist(index == 1 ? _firstDataOffset : 2));
    _next++;
    if (index < total - 1) return null;
    return _finish(Parsed(_log()));
  }

  void reset() {
    _total = null;
    _interval = 0;
    _next = 1;
    _reportedSeconds = null;
    _values.clear();
  }

  ParseResult<SlotLog>? _start(List<int> b) {
    reset();
    _interval = b[3] == 0 ? _defaultInterval : b[3];
    if (b[2] <= 1) return _finish(Parsed(_log()));
    _total = b[2];
    return null;
  }

  SlotLog _log() => SlotLog(
    intervalMinutes: _interval,
    values: _values,
    reportedSeconds: _reportedSeconds,
  );

  ParseResult<SlotLog> _finish(ParseResult<SlotLog> result) {
    reset();
    return result;
  }
}
