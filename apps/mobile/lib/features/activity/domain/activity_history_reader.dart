import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';

const defaultStepGoal = 8000;

@immutable
final class DailyActivity {
  const new({
    required this.date,
    required this.steps,
    required this.activeKilocalories,
    required this.distanceMeters,
  });

  final LocalDate date;
  final int steps;
  final double activeKilocalories;
  final double distanceMeters;

  DailyValue get activeLoad => (date: date, value: activeKilocalories);
}

@immutable
final class ActivitySlot {
  const new({
    required this.start,
    required this.utcOffset,
    required this.duration,
    required this.steps,
    required this.activeKilocalories,
    required this.distanceMeters,
  });

  final DateTime start;
  final Duration utcOffset;
  final Duration duration;
  final int steps;
  final double activeKilocalories;
  final double distanceMeters;

  DateTime get _wall => start.toUtc().add(utcOffset);

  LocalDate get date => LocalDate.fromInstant(start, utcOffset);

  int get localHour => _wall.hour;
}

abstract interface class ActivityHistoryReader {
  Future<List<DailyActivity>> dailyActivity({
    required LocalDate from,
    required LocalDate to,
  });

  Future<List<ActivitySlot>> activitySlots({
    required LocalDate from,
    required LocalDate to,
  });
}

final class EmptyActivityHistoryReader implements ActivityHistoryReader {
  const new();

  @override
  Future<List<DailyActivity>> dailyActivity({
    required LocalDate from,
    required LocalDate to,
  }) async => const [];

  @override
  Future<List<ActivitySlot>> activitySlots({
    required LocalDate from,
    required LocalDate to,
  }) async => const [];
}
