import 'package:meta/meta.dart';
import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v1/frame.dart';
import 'package:ring_protocol/src/v1/response.dart';

@immutable
final class BatteryReading {
  const new({required this.percent, required this.charging});

  final int percent;
  final bool charging;

  @override
  bool operator ==(Object other) =>
      other is BatteryReading &&
      other.percent == percent &&
      other.charging == charging;

  @override
  int get hashCode => Object.hash(percent, charging);
}

ParseResult<BatteryReading> parseBattery(V1Frame frame) {
  final error = commandError(frame, V1Command.battery.id);
  if (error != null) return ParseFailure(error);
  final percent = frame.payload[0];
  if (percent > 100) {
    return ParseFailure(ByteOutOfRange(index: 1, value: percent));
  }
  return Parsed(
    BatteryReading(percent: percent, charging: frame.payload[1] != 0),
  );
}
