import 'package:meta/meta.dart';
import 'package:ring_protocol/src/bytes.dart';
import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v1/frame.dart';
import 'package:ring_protocol/src/v1/response.dart';

abstract final class NotifyType {
  static const heartRate = 0x01;
  static const bloodPressure = 0x02;
  static const spo2 = 0x03;
  static const steps = 0x04;
  static const temperature = 0x05;
  static const activity = 0x07;
  static const battery = 0x0C;
  static const liveActivity = 0x12;
}

@immutable
sealed class DeviceNotification {
  const new(this.type);

  final int type;
}

final class NewDataAvailable extends DeviceNotification {
  const new(super.type);

  @override
  bool operator ==(Object other) =>
      other is NewDataAvailable && other.type == type;

  @override
  int get hashCode => type.hashCode;
}

final class BatteryNotification extends DeviceNotification {
  const new({required this.percent, required this.charging})
    : super(NotifyType.battery);

  final int percent;
  final bool charging;

  @override
  bool operator ==(Object other) =>
      other is BatteryNotification &&
      other.percent == percent &&
      other.charging == charging;

  @override
  int get hashCode => Object.hash(percent, charging);
}

final class LiveActivityNotification extends DeviceNotification {
  const new({
    required this.steps,
    required this.calories,
    required this.distanceMeters,
  }) : super(NotifyType.liveActivity);

  final int steps;
  final int calories;
  final int distanceMeters;

  @override
  bool operator ==(Object other) =>
      other is LiveActivityNotification &&
      other.steps == steps &&
      other.calories == calories &&
      other.distanceMeters == distanceMeters;

  @override
  int get hashCode => Object.hash(steps, calories, distanceMeters);
}

final class TemperatureNotification extends DeviceNotification {
  new(List<int> raw)
    : raw = List.unmodifiable(raw),
      super(NotifyType.temperature);

  final List<int> raw;

  // No source documents this payload. This applies the only temperature
  // encoding known for the ring (big data 0x25: byte / 10 + 20) to byte 2.
  double? get provisionalCelsius => raw[0] == 0 ? null : raw[0] / 10 + 20;

  @override
  bool operator ==(Object other) =>
      other is TemperatureNotification && listEquals(other.raw, raw);

  @override
  int get hashCode => Object.hashAll(raw);
}

final class UnknownNotification extends DeviceNotification {
  new(super.type, List<int> raw) : raw = List.unmodifiable(raw);

  final List<int> raw;

  @override
  bool operator ==(Object other) =>
      other is UnknownNotification &&
      other.type == type &&
      listEquals(other.raw, raw);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(raw));
}

ParseResult<DeviceNotification> parseDeviceNotification(V1Frame frame) {
  final error = commandError(frame, V1Command.deviceNotify.id);
  if (error != null) return ParseFailure(error);
  final b = frameBytes(frame);
  final type = b[1];
  return switch (type) {
    NotifyType.heartRate ||
    NotifyType.spo2 ||
    NotifyType.steps => Parsed(NewDataAvailable(type)),
    NotifyType.battery => _battery(b),
    NotifyType.liveActivity => Parsed(
      LiveActivityNotification(
        steps: uint24be(b, 2),
        calories: uint24be(b, 5),
        distanceMeters: uint24be(b, 8),
      ),
    ),
    NotifyType.temperature => Parsed(TemperatureNotification(b.sublist(2))),
    _ => Parsed(UnknownNotification(type, b.sublist(2))),
  };
}

ParseResult<DeviceNotification> _battery(List<int> b) {
  if (b[2] > 100) return ParseFailure(ByteOutOfRange(index: 2, value: b[2]));
  return Parsed(BatteryNotification(percent: b[2], charging: b[3] == 1));
}
