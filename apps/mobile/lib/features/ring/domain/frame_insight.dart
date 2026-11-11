import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:open_ring/features/ring/domain/checksum_rule.dart';
import 'package:open_ring/features/ring/domain/frame_log_entry.dart';
import 'package:ring_protocol/ring_protocol.dart';

@immutable
sealed class FrameReading {
  const new();
}

final class BatteryFrame extends FrameReading {
  const new(this.reading);

  final BatteryReading reading;
}

final class CapabilitiesFrame extends FrameReading {
  const new(this.capabilities);

  final DeviceCapabilities capabilities;
}

final class AutoMonitorFrame extends FrameReading {
  const new({
    required this.monitor,
    required this.enabled,
    required this.rawValue,
  });

  final AutoMonitor monitor;
  final bool enabled;
  final int rawValue;
}

final class TodayTotalsFrame extends FrameReading {
  const new({required this.bigEndian, required this.littleEndian});

  final TodayTotals bigEndian;
  final TodayTotals littleEndian;
}

final class RealTimeFrame extends FrameReading {
  const new(this.reading);

  final RealTimeReading reading;
}

final class RealTimeStopFrame extends FrameReading {
  const new();
}

final class NotifyFrame extends FrameReading {
  const new(this.notification);

  final DeviceNotification notification;
}

final class FlaggedReplyFrame extends FrameReading {
  const new(this.command);

  final int command;
}

final class UnexpectedByteFrame extends FrameReading {
  const new({required this.command, required this.index, required this.value});

  final int command;
  final int index;
  final int value;
}

@immutable
final class FrameInsight {
  const new({required this.checksums, this.reading});

  final Set<ChecksumRule> checksums;
  final FrameReading? reading;

  BatteryReading? get battery => switch (reading) {
    BatteryFrame(:final reading) => reading,
    _ => null,
  };

  static FrameInsight? of(FrameLogEntry entry) {
    if (entry.bytes.length != V1Frame.length) return null;
    final parsed = {
      for (final rule in ChecksumRule.values)
        if (rule.codec.decode(entry.bytes) case Parsed(:final value))
          rule: value,
    };
    final frame = parsed.values.firstOrNull;
    final incoming = entry.direction == FrameDirection.rx;
    return FrameInsight(
      checksums: parsed.keys.toSet(),
      reading: incoming && frame != null ? _read(frame) : null,
    );
  }

  static FrameReading? _read(V1Frame frame) {
    final base = frame.command & ~V1Frame.errorBit;
    if (base == V1ExtraCommandId.stopRealTime) {
      return _wrap(
        frame,
        parseRealTimeStop(frame),
        (_) => const RealTimeStopFrame(),
      );
    }
    return switch (V1Command.fromId(base)) {
      V1Command.battery => _wrap(frame, parseBattery(frame), BatteryFrame.new),
      V1Command.setDateTime => _wrap(
        frame,
        parseSetTime(frame),
        CapabilitiesFrame.new,
      ),
      V1Command.autoSpo2Setting => _monitor(frame, AutoMonitor.spo2),
      V1Command.autoStressSetting => _monitor(frame, AutoMonitor.stress),
      V1Command.autoHrvSetting => _monitor(frame, AutoMonitor.hrv),
      V1Command.todayActivity => _totals(frame),
      V1Command.realTimeData => _wrap(
        frame,
        parseRealTimeReading(frame),
        RealTimeFrame.new,
      ),
      V1Command.deviceNotify => _wrap(
        frame,
        parseDeviceNotification(frame),
        NotifyFrame.new,
      ),
      _ => null,
    };
  }

  static FrameReading? _monitor(V1Frame frame, AutoMonitor monitor) => _wrap(
    frame,
    parseAutoMonitor(frame, monitor),
    (enabled) => AutoMonitorFrame(
      monitor: monitor,
      enabled: enabled,
      rawValue: frame.payload[1],
    ),
  );

  static FrameReading? _totals(V1Frame frame) => switch ((
    parseTodayTotals(frame),
    parseTodayTotals(frame, order: Endian.little),
  )) {
    (Parsed(value: final big), Parsed(value: final little)) => TodayTotalsFrame(
      bigEndian: big,
      littleEndian: little,
    ),
    (final big, _) => _wrap(frame, big, (_) => null),
  };

  static FrameReading? _wrap<T>(
    V1Frame frame,
    ParseResult<T> result,
    FrameReading? Function(T value) reading,
  ) => switch (result) {
    Parsed(:final value) => reading(value),
    ParseFailure(error: ErrorResponse(:final command)) => FlaggedReplyFrame(
      command,
    ),
    ParseFailure(error: ByteOutOfRange(:final index, :final value)) =>
      UnexpectedByteFrame(command: frame.command, index: index, value: value),
    ParseFailure() => null,
  };
}
