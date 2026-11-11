import 'package:meta/meta.dart';
import 'package:ring_protocol/src/bytes.dart';
import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v2/big_data.dart';

const temperatureRequestPayload = [0x02];

@immutable
final class TemperatureDay {
  new({required this.daysAgo, required List<double?> halfHourly})
    : halfHourly = List.unmodifiable(halfHourly);

  final int daysAgo;
  final List<double?> halfHourly;

  @override
  bool operator ==(Object other) =>
      other is TemperatureDay &&
      other.daysAgo == daysAgo &&
      listEquals(other.halfHourly, halfHourly);

  @override
  int get hashCode => Object.hash(daysAgo, Object.hashAll(halfHourly));
}

const _slotsPerDay = 48;
const _dayHeaderLength = 2;

ParseResult<List<TemperatureDay>> parseTemperature(BigDataPacket packet) {
  final idError = bigDataIdError(packet, BigDataId.temperature);
  if (idError != null) return ParseFailure(idError);
  final p = packet.payload;
  final days = <TemperatureDay>[];
  var offset = 0;
  while (offset < p.length) {
    final start = offset + _dayHeaderLength;
    if (start > p.length) {
      return ParseFailure(WrongLength(expected: start, actual: p.length));
    }
    final slots = (p.length - start).clamp(0, _slotsPerDay);
    days.add(
      TemperatureDay(
        daysAgo: p[offset],
        halfHourly: [
          for (var i = start; i < start + slots; i++)
            if (p[i] == 0) null else p[i] / 10 + 20,
        ],
      ),
    );
    offset = start + slots;
  }
  return Parsed(List.unmodifiable(days));
}
