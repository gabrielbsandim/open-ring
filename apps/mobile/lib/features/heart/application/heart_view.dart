import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';

typedef TimedValue = ({DateTime at, double value});

@immutable
final class BaselineInput {
  const new({required this.today, required this.baseline});

  final double? today;
  final BaselineResult baseline;

  BaselineDeviation? get deviation {
    final value = today;
    final ready = baseline;
    if (value == null || ready is! BaselineReady) return null;
    return ready.compare(value);
  }
}

@immutable
final class HeartBaselines {
  const new({required this.restingHeartRate, required this.hrv});

  final BaselineInput restingHeartRate;
  final BaselineInput hrv;
}

@immutable
final class HourlySeries {
  new(List<double?> hours, {this.mean, this.min, this.max})
    : hours = List.unmodifiable(hours);

  factory of(DateTime dayStart, Iterable<TimedValue> values) {
    final buckets = List.generate(Duration.hoursPerDay, (_) => <double>[]);
    for (final v in values) {
      final hour = v.at.difference(dayStart).inMinutes ~/ 60;
      if (hour < 0 || hour >= Duration.hoursPerDay) continue;
      buckets[hour].add(v.value);
    }
    final all = buckets.expand((b) => b).toList();
    final hours = [
      for (final b in buckets)
        if (b.isEmpty) null else _mean(b),
    ];
    if (all.isEmpty) return HourlySeries(hours);
    return HourlySeries(
      hours,
      mean: _mean(all),
      min: all.reduce((a, b) => a < b ? a : b),
      max: all.reduce((a, b) => a > b ? a : b),
    );
  }

  final List<double?> hours;
  final double? mean;
  final double? min;
  final double? max;

  bool get isEmpty => mean == null;

  static double _mean(List<double> values) =>
      values.reduce((a, b) => a + b) / values.length;
}

@immutable
final class HeartDayView {
  const new({
    required this.dayStart,
    required this.until,
    required this.utcOffset,
    required this.heartRate,
    required this.hrv,
    required this.spo2,
    required this.stress,
    required this.baselines,
    required this.spo2Night,
    required this.stressSummary,
  });

  final DateTime dayStart;
  final DateTime until;
  final Duration utcOffset;
  final HourlySeries heartRate;
  final HourlySeries hrv;
  final HourlySeries spo2;
  final HourlySeries stress;
  final HeartBaselines baselines;
  final Spo2NightSummary? spo2Night;
  final StressDaySummary? stressSummary;

  bool get isEmpty =>
      heartRate.isEmpty &&
      hrv.isEmpty &&
      spo2.isEmpty &&
      stress.isEmpty &&
      spo2Night == null &&
      baselines.restingHeartRate.today == null &&
      baselines.hrv.today == null;
}
