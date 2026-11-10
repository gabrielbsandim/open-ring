import 'package:meta/meta.dart';
import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v1/frame.dart';

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
  if (frame.command != V1Command.battery.id) {
    return ParseFailure(
      UnexpectedCommand(expected: V1Command.battery.id, actual: frame.command),
    );
  }
  final percent = frame.payload[0];
  if (percent > 100) {
    return ParseFailure(ByteOutOfRange(index: 1, value: percent));
  }
  return Parsed(
    BatteryReading(percent: percent, charging: frame.payload[1] != 0),
  );
}
