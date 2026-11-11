import 'package:meta/meta.dart';

@immutable
final class OffsetTime {
  const new({required this.utcMs, required this.offsetMinutes});

  factory of(DateTime at) => OffsetTime(
    utcMs: at.millisecondsSinceEpoch,
    offsetMinutes: at.timeZoneOffset.inMinutes,
  );

  final int utcMs;
  final int offsetMinutes;

  OffsetTime plus(Duration duration) => OffsetTime(
    utcMs: utcMs + duration.inMilliseconds,
    offsetMinutes: offsetMinutes,
  );

  String toIso8601() => '${_wallClock(offsetMinutes)}${_offsetSuffix()}';

  String toUtcIso8601() => '${_wallClock(0)}Z';

  String _wallClock(int offset) {
    final wall = DateTime.fromMillisecondsSinceEpoch(
      utcMs + offset * Duration.millisecondsPerMinute,
      isUtc: true,
    );
    final fraction = wall.millisecond == 0
        ? ''
        : '.${_pad(wall.millisecond, 3)}';
    return '${_pad(wall.year, 4)}-${_pad(wall.month)}-${_pad(wall.day)}'
        'T${_pad(wall.hour)}:${_pad(wall.minute)}:${_pad(wall.second)}'
        '$fraction';
  }

  String _offsetSuffix() {
    final sign = offsetMinutes < 0 ? '-' : '+';
    final minutes = offsetMinutes.abs();
    return '$sign${_pad(minutes ~/ 60)}:${_pad(minutes % 60)}';
  }

  static String _pad(int value, [int width = 2]) =>
      value.toString().padLeft(width, '0');

  @override
  bool operator ==(Object other) =>
      other is OffsetTime &&
      other.utcMs == utcMs &&
      other.offsetMinutes == offsetMinutes;

  @override
  int get hashCode => Object.hash(utcMs, offsetMinutes);

  @override
  String toString() => toIso8601();
}
