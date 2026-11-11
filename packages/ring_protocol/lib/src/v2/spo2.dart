import 'package:meta/meta.dart';
import 'package:ring_protocol/src/bytes.dart';
import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v2/big_data.dart';

@immutable
final class Spo2Range {
  const new({required this.min, required this.max});

  final int min;
  final int max;

  bool get hasData => min > 0 && max > 0;

  @override
  bool operator ==(Object other) =>
      other is Spo2Range && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

@immutable
final class Spo2Day {
  new({required this.daysAgo, required List<Spo2Range> hourly})
    : hourly = List.unmodifiable(hourly);

  final int daysAgo;
  final List<Spo2Range> hourly;

  @override
  bool operator ==(Object other) =>
      other is Spo2Day &&
      other.daysAgo == daysAgo &&
      listEquals(other.hourly, hourly);

  @override
  int get hashCode => Object.hash(daysAgo, Object.hashAll(hourly));
}

const _hoursPerDay = 24;

ParseResult<List<Spo2Day>> parseSpo2(BigDataPacket packet) {
  final idError = bigDataIdError(packet, BigDataId.spo2);
  if (idError != null) return ParseFailure(idError);
  final p = packet.payload;
  final days = <Spo2Day>[];
  var offset = 0;
  while (offset < p.length) {
    final hours = (p.length - offset - 1).clamp(0, _hoursPerDay * 2);
    if (hours.isOdd) {
      return ParseFailure(
        WrongLength(expected: offset + 2 + hours, actual: p.length),
      );
    }
    final start = offset + 1;
    days.add(
      Spo2Day(
        daysAgo: p[offset],
        hourly: [
          for (var i = start; i < start + hours; i += 2)
            Spo2Range(min: p[i], max: p[i + 1]),
        ],
      ),
    );
    offset = start + hours;
  }
  return Parsed(List.unmodifiable(days));
}
