import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/heart/application/heart_view.dart';
import 'package:open_ring/features/trends/domain/trend_history.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';

const readinessTrendDays = 14;

@immutable
final class ReadinessTrend {
  new({required this.today, required List<int?> values})
    : values = List.unmodifiable(values);

  factory collect({
    required LocalDate today,
    required TrendHistory history,
    required Iterable<DailyActivity> activity,
  }) {
    final resting = history.values(TrendMetric.restingHeartRate);
    final hrv = history.values(TrendMetric.hrv);
    final sleep = history.values(TrendMetric.sleepScore);
    final loads = [for (final day in activity) day.activeLoad];
    int? scoreOn(LocalDate date) {
      final result = readiness(
        sleepScore: _valueOn(sleep, date)?.round(),
        hrv: BaselineInput(
          today: _valueOn(hrv, date),
          baseline: hrvBaseline(hrv, today: date),
        ).deviation,
        restingHeartRate: BaselineInput(
          today: _valueOn(resting, date),
          baseline: restingHeartRateBaseline(resting, today: date),
        ).deviation,
        activityLoad: activityLoad(loads, today: date),
      );
      return switch (result) {
        Scored(:final value) => value,
        InsufficientData() => null,
      };
    }

    return ReadinessTrend(
      today: today,
      values: [
        for (var age = readinessTrendDays - 1; age >= 0; age--)
          scoreOn(today.addDays(-age)),
      ],
    );
  }

  final LocalDate today;
  final List<int?> values;

  LocalDate get firstDate => today.addDays(1 - values.length);

  List<int> get scored => values.nonNulls.toList();

  bool get isEmpty => scored.isEmpty;

  int? get average {
    final scored = this.scored;
    if (scored.isEmpty) return null;
    return (scored.reduce((a, b) => a + b) / scored.length).round();
  }

  int? get lowest {
    final scored = this.scored;
    if (scored.isEmpty) return null;
    return scored.reduce((a, b) => a < b ? a : b);
  }

  int? get highest {
    final scored = this.scored;
    if (scored.isEmpty) return null;
    return scored.reduce((a, b) => a > b ? a : b);
  }

  static double? _valueOn(List<DailyValue> values, LocalDate date) {
    double? found;
    for (final v in values) {
      if (v.date == date) found = v.value;
    }
    return found;
  }
}
