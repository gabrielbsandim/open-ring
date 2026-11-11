import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:ring_protocol/src/bytes.dart';
import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v1/frame.dart';
import 'package:ring_protocol/src/v1/response.dart';

Uint8List activityLogRequest({
  int daysAgo = 0,
  V1FrameCodec codec = const V1FrameCodec(),
}) {
  checkByte(daysAgo, 'daysAgo');
  return codec.encode(V1Command.activityLog, [daysAgo, 0x0F, 0x00, 0x5F, 0x01]);
}

@immutable
final class ActivityRecord {
  const new({
    required this.year,
    required this.month,
    required this.day,
    required this.quarterOfDay,
    required this.calories,
    required this.steps,
    required this.distanceMeters,
  });

  final int year;
  final int month;
  final int day;
  final int quarterOfDay;
  final int calories;
  final int steps;
  final int distanceMeters;

  int get minuteOfDay => quarterOfDay * 15;

  @override
  bool operator ==(Object other) =>
      other is ActivityRecord &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.quarterOfDay == quarterOfDay &&
      other.calories == calories &&
      other.steps == steps &&
      other.distanceMeters == distanceMeters;

  @override
  int get hashCode => Object.hash(
    year,
    month,
    day,
    quarterOfDay,
    calories,
    steps,
    distanceMeters,
  );

  @override
  String toString() =>
      'ActivityRecord($year-$month-$day q$quarterOfDay, $steps steps)';
}

final class ActivityLogAssembler {
  static const noData = 0xFF;
  static const header = 0xF0;

  bool _newCalorieProtocol = false;
  final _records = <ActivityRecord>[];

  ParseResult<List<ActivityRecord>>? add(V1Frame frame) {
    final error = commandError(frame, V1Command.activityLog.id);
    if (error != null) return _finish(ParseFailure(error));
    final b = frameBytes(frame);
    switch (b[1]) {
      case noData:
        return _finish(const Parsed([]));
      case header:
        reset();
        _newCalorieProtocol = b[3] == 1;
        return null;
    }
    switch (_record(b)) {
      case ParseFailure(:final error):
        return _finish(ParseFailure(error));
      case Parsed(:final value):
        _records.add(value);
    }
    if (b[5] < b[6] - 1) return null;
    return _finish(Parsed(List.unmodifiable(_records)));
  }

  void reset() {
    _newCalorieProtocol = false;
    _records.clear();
  }

  ParseResult<ActivityRecord> _record(List<int> b) {
    final year = fromBcd(b[1]);
    if (year == null) {
      return ParseFailure(ByteOutOfRange(index: 1, value: b[1]));
    }
    final month = fromBcd(b[2]);
    if (month == null || month < 1 || month > 12) {
      return ParseFailure(ByteOutOfRange(index: 2, value: b[2]));
    }
    final day = fromBcd(b[3]);
    if (day == null || day < 1 || day > 31) {
      return ParseFailure(ByteOutOfRange(index: 3, value: b[3]));
    }
    if (b[4] > 95) return ParseFailure(ByteOutOfRange(index: 4, value: b[4]));
    final calories = uint16le(b, 7);
    return Parsed(
      ActivityRecord(
        year: 2000 + year,
        month: month,
        day: day,
        quarterOfDay: b[4],
        calories: _newCalorieProtocol ? calories * 10 : calories,
        steps: uint16le(b, 9),
        distanceMeters: uint16le(b, 11),
      ),
    );
  }

  ParseResult<List<ActivityRecord>> _finish(
    ParseResult<List<ActivityRecord>> result,
  ) {
    reset();
    return result;
  }
}

Uint8List todayTotalsRequest({V1FrameCodec codec = const V1FrameCodec()}) =>
    codec.encode(V1Command.todayActivity);

@immutable
final class TodayTotals {
  const new({
    required this.totalSteps,
    required this.runningSteps,
    required this.calories,
    required this.walkingDistanceMeters,
    required this.activeMinutes,
  });

  final int totalSteps;
  final int runningSteps;
  final int calories;
  final int walkingDistanceMeters;
  final int activeMinutes;

  @override
  bool operator ==(Object other) =>
      other is TodayTotals &&
      other.totalSteps == totalSteps &&
      other.runningSteps == runningSteps &&
      other.calories == calories &&
      other.walkingDistanceMeters == walkingDistanceMeters &&
      other.activeMinutes == activeMinutes;

  @override
  int get hashCode => Object.hash(
    totalSteps,
    runningSteps,
    calories,
    walkingDistanceMeters,
    activeMinutes,
  );
}

ParseResult<TodayTotals> parseTodayTotals(
  V1Frame frame, {
  Endian order = Endian.big,
}) {
  final error = commandError(frame, V1Command.todayActivity.id);
  if (error != null) return ParseFailure(error);
  final b = frameBytes(frame);
  // Byte order is a guess: Puxtril gives only 24 bit fields, and Gadgetbridge
  // reads the same counters big endian in device notify 0x12.
  final little = order == Endian.little;
  int field24(int offset) => little ? uint24le(b, offset) : uint24be(b, offset);
  return Parsed(
    TodayTotals(
      totalSteps: field24(1),
      runningSteps: field24(4),
      calories: field24(7),
      walkingDistanceMeters: field24(10),
      activeMinutes: little ? uint16le(b, 13) : uint16be(b, 13),
    ),
  );
}
