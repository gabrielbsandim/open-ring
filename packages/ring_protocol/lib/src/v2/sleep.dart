import 'package:meta/meta.dart';
import 'package:ring_protocol/src/bytes.dart';
import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v2/big_data.dart';

abstract final class SleepStageCode {
  static const noData = 0;
  static const error = 1;
  static const light = 2;
  static const deep = 3;
  static const rem = 4;
  static const awake = 5;
}

@immutable
final class SleepPeriod {
  const new({required this.stage, required this.minutes});

  final int stage;
  final int minutes;

  @override
  bool operator ==(Object other) =>
      other is SleepPeriod && other.stage == stage && other.minutes == minutes;

  @override
  int get hashCode => Object.hash(stage, minutes);

  @override
  String toString() => 'SleepPeriod($stage, $minutes min)';
}

@immutable
final class SleepDay {
  new({
    required this.daysAgo,
    required this.startMinute,
    required this.endMinute,
    required List<SleepPeriod> periods,
  }) : periods = List.unmodifiable(periods);

  final int daysAgo;
  final int startMinute;
  final int endMinute;
  final List<SleepPeriod> periods;

  @override
  bool operator ==(Object other) =>
      other is SleepDay &&
      other.daysAgo == daysAgo &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute &&
      listEquals(other.periods, periods);

  @override
  int get hashCode =>
      Object.hash(daysAgo, startMinute, endMinute, Object.hashAll(periods));
}

const _dayHeaderLength = 6;
const _startEndLength = 4;

ParseResult<List<SleepDay>> parseSleep(BigDataPacket packet) {
  final idError = bigDataIdError(packet, BigDataId.sleep);
  if (idError != null) return ParseFailure(idError);
  final p = packet.payload;
  if (p.isEmpty) return const Parsed([]);
  final days = <SleepDay>[];
  var offset = 1;
  for (var d = 0; d < p[0]; d++) {
    final day = _day(p, offset);
    switch (day) {
      case ParseFailure(:final error):
        return ParseFailure(error);
      case Parsed(:final value):
        days.add(value.day);
        offset = value.next;
    }
  }
  return Parsed(List.unmodifiable(days));
}

ParseResult<({SleepDay day, int next})> _day(List<int> p, int offset) {
  if (p.length < offset + _dayHeaderLength) {
    return ParseFailure(
      WrongLength(expected: offset + _dayHeaderLength, actual: p.length),
    );
  }
  final dayBytes = p[offset + 1];
  if (dayBytes < _startEndLength) {
    return ParseFailure(ByteOutOfRange(index: offset + 1, value: dayBytes));
  }
  final end = offset + 2 + dayBytes;
  if (p.length < end) {
    return ParseFailure(WrongLength(expected: end, actual: p.length));
  }
  final periods = [
    for (var i = offset + _dayHeaderLength; i + 1 < end; i += 2)
      SleepPeriod(stage: p[i], minutes: p[i + 1]),
  ];
  return Parsed((
    day: SleepDay(
      daysAgo: p[offset],
      startMinute: int16le(p, offset + 2),
      endMinute: int16le(p, offset + 4),
      periods: periods,
    ),
    next: end,
  ));
}
