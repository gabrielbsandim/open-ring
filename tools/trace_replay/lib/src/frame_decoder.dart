import 'package:meta/meta.dart';
import 'package:ring_protocol/ring_protocol.dart';
import 'package:trace_replay/src/checksum_check.dart';
import 'package:trace_replay/src/describe.dart';
import 'package:trace_replay/src/hex.dart';
import 'package:trace_replay/src/trace.dart';

@immutable
final class DecodedFrame {
  const new(this.entry, {this.checksum, this.meaning, this.failure});

  final TraceEntry entry;
  final ChecksumCheck? checksum;
  final String? meaning;
  final String? failure;

  bool get failed => failure != null;
}

typedef _Outcome = ({String? meaning, String? failure});

_Outcome _ok(String meaning) => (meaning: meaning, failure: null);

_Outcome _bad(String failure) => (meaning: null, failure: failure);

_Outcome _from<T>(
  ParseResult<T>? result,
  String Function(T value) describe, {
  String pending = 'part, waiting for more frames',
}) => switch (result) {
  null => _ok(pending),
  Parsed(:final value) => _ok(describe(value)),
  ParseFailure(:final error) => _bad(describeError(error)),
};

// Assemblers keep state across frames, so one decoder must see the whole trace
// in order, the same way the driver saw it.
final class TraceDecoder {
  final _activity = ActivityLogAssembler();
  final _heartRate = SlotLogAssembler.heartRate();
  final _stress = SlotLogAssembler.stress();
  final _hrv = SlotLogAssembler.hrv();
  final _bigData = BigDataAssembler();

  DecodedFrame decode(TraceEntry entry) {
    final channel = entry.channel;
    if (channel == null) {
      return DecodedFrame(
        entry,
        failure: 'unknown characteristic ${entry.characteristic}',
      );
    }
    if (!channel.isBigData) return _v1(entry);
    final outcome = entry.isTx
        ? _bigDataRequest(entry.bytes)
        : _bigDataChunk(entry.bytes);
    return DecodedFrame(
      entry,
      meaning: outcome.meaning,
      failure: outcome.failure,
    );
  }

  DecodedFrame _v1(TraceEntry entry) {
    final bytes = entry.bytes;
    if (bytes.length != V1Frame.length) {
      return DecodedFrame(
        entry,
        failure: describeError(
          WrongLength(expected: V1Frame.length, actual: bytes.length),
        ),
      );
    }
    final check = ChecksumCheck.of(bytes);
    final rule = check.satisfiedRule;
    if (rule == null) {
      return DecodedFrame(
        entry,
        checksum: check,
        failure: 'checksum fails under both rules, payload not decoded',
      );
    }
    final outcome = switch (rule.codec.decode(bytes)) {
      Parsed(:final value) when entry.isTx => _ok(describeRequest(value)),
      Parsed(:final value) => _response(value),
      ParseFailure(:final error) => _bad(describeError(error)),
    };
    return DecodedFrame(
      entry,
      checksum: check,
      meaning: outcome.meaning,
      failure: outcome.failure,
    );
  }

  _Outcome _response(V1Frame frame) {
    final command = frame.command;
    final base = command & ~V1Frame.errorBit;
    final flaggedName = commandName(base);
    if (command != base && flaggedName != null) {
      return _bad('error response for $flaggedName (${Hex.id(command)})');
    }
    if (command == V1ExtraCommandId.stopRealTime) {
      return _from(parseRealTimeStop(frame), (_) => 'stopRealTime ack');
    }
    final known = V1Command.fromId(command);
    if (known == null) return _bad('no parser for command ${Hex.id(command)}');
    final label = known.name;
    return switch (known) {
      V1Command.setDateTime => _from(
        parseSetTime(frame),
        (c) => '$label reply, capabilities: ${describeCapabilities(c)}',
      ),
      V1Command.battery => _from(
        parseBattery(frame),
        (b) => '$label ${describeBattery(b)}',
      ),
      V1Command.heartRateLog => _slot(_heartRate, frame),
      V1Command.stressLog => _slot(_stress, frame),
      V1Command.hrvLog => _slot(_hrv, frame),
      V1Command.autoHeartRateSetting => _heartRateSetting(frame),
      V1Command.autoSpo2Setting => _monitor(frame, AutoMonitor.spo2),
      V1Command.autoStressSetting => _monitor(frame, AutoMonitor.stress),
      V1Command.autoHrvSetting => _monitor(frame, AutoMonitor.hrv),
      V1Command.activityLog => _from(
        _activity.add(frame),
        (records) => '$label complete: ${describeActivity(records)}',
        pending: '$label part, waiting for more frames',
      ),
      V1Command.todayActivity => _from(
        parseTodayTotals(frame),
        (t) => '$label ${describeTodayTotals(t)}',
      ),
      V1Command.findDevice => _from(
        parseFindDevice(frame),
        (_) => '$label ack',
      ),
      V1Command.realTimeData => _from(
        parseRealTimeReading(frame),
        describeRealTime,
      ),
      V1Command.deviceNotify => _from(
        parseDeviceNotification(frame),
        describeNotification,
      ),
      _ => _bad('no parser for $label replies (${Hex.id(command)})'),
    };
  }

  _Outcome _slot(SlotLogAssembler assembler, V1Frame frame) => _from(
    assembler.add(frame),
    (log) => '${assembler.command.name} complete: ${describeSlotLog(log)}',
    pending: '${assembler.command.name} part ${frame.payload[0]}',
  );

  _Outcome _heartRateSetting(V1Frame frame) {
    if (frame.payload[0] != SettingAction.read.id) {
      return _from(
        parseSettingAck(frame, V1Command.autoHeartRateSetting),
        (action) => 'autoHeartRateSetting ${action.name} ack',
      );
    }
    return _from(
      parseAutoHeartRateSetting(frame),
      (s) =>
          'autoHeartRateSetting ${s.enabled ? 'on' : 'off'}, '
          'every ${s.intervalMinutes} min',
    );
  }

  _Outcome _monitor(V1Frame frame, AutoMonitor monitor) {
    final name = monitor.command.name;
    if (frame.payload[0] != SettingAction.read.id) {
      return _from(
        parseSettingAck(frame, monitor.command),
        (action) => '$name ${action.name} ack',
      );
    }
    return _from(
      parseAutoMonitor(frame, monitor),
      (enabled) => '$name ${enabled ? 'on' : 'off'}',
    );
  }

  _Outcome _bigDataRequest(List<int> bytes) {
    if (bytes.length < BigDataFrame.headerLength) {
      return _bad(
        describeError(
          WrongLength(
            expected: BigDataFrame.headerLength,
            actual: bytes.length,
          ),
        ),
      );
    }
    if (bytes.first != BigDataFrame.magic) {
      return _bad(
        describeError(
          UnexpectedCommand(expected: BigDataFrame.magic, actual: bytes.first),
        ),
      );
    }
    final name = bigDataName(bytes[1]) ?? 'unknown id ${Hex.id(bytes[1])}';
    final payload = bytes.sublist(BigDataFrame.headerLength);
    return _ok('big data request $name, payload [${Hex.spaced(payload)}]');
  }

  _Outcome _bigDataChunk(List<int> bytes) => switch (_bigData.add(bytes)) {
    null => _ok('big data chunk, ${bytes.length} bytes, waiting for more'),
    Parsed(:final value) => _bigDataPacket(value),
    ParseFailure(:final error) => _bad('big data ${describeError(error)}'),
  };

  _Outcome _bigDataPacket(BigDataPacket packet) => switch (packet.dataId) {
    BigDataId.temperature => _from(
      parseTemperature(packet),
      (days) => 'big data temperature: ${describeTemperature(days)}',
    ),
    BigDataId.sleep => _from(
      parseSleep(packet),
      (days) => 'big data sleep: ${describeSleep(days)}',
    ),
    BigDataId.spo2 => _from(
      parseSpo2(packet),
      (days) => 'big data spo2: ${describeSpo2(days)}',
    ),
    _ => _bad(
      'no parser for big data id ${Hex.id(packet.dataId)} '
      '(${packet.payload.length} byte payload)',
    ),
  };
}

String describeRequest(V1Frame frame) {
  final name = commandName(frame.command) ?? 'command ${Hex.id(frame.command)}';
  final p = frame.payload;
  return switch (V1Command.fromId(frame.command)) {
    V1Command.setDateTime =>
      '$name request ${_bcdDateTime(p)}, language ${p[6]}',
    V1Command.heartRateLog =>
      '$name request for the day starting ${_wallClock(p)} (ring wall clock)',
    V1Command.activityLog ||
    V1Command.hrvLog => '$name request, ${p[0]} days ago',
    V1Command.realTimeData => '$name request, type ${p[0]}, action ${p[1]}',
    _ => '$name request',
  };
}

String _bcdDateTime(List<int> p) {
  String bcd(int byte) => Hex.byte(byte);
  return '20${bcd(p[0])}-${bcd(p[1])}-${bcd(p[2])} '
      '${bcd(p[3])}:${bcd(p[4])}:${bcd(p[5])}';
}

String _wallClock(List<int> p) {
  final seconds = p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
  final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  return stamp(at);
}
