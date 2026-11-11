import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/heart/application/heart_view.dart';
import 'package:open_ring/features/sleep/application/sleep_view.dart';

@immutable
final class ReadinessView {
  const new({
    required this.date,
    required this.score,
    required this.sleep,
    required this.restingHeartRate,
    required this.hrv,
    required this.activityLoad,
  });

  final LocalDate date;
  final ScoreResult<ReadinessFactor> score;
  final SleepDayView sleep;
  final BaselineInput restingHeartRate;
  final BaselineInput hrv;
  final ActivityLoad? activityLoad;

  int? get value => switch (score) {
    Scored(:final value) => value,
    InsufficientData() => null,
  };

  Contribution<ReadinessFactor>? contribution(ReadinessFactor factor) =>
      switch (score) {
        final Scored<ReadinessFactor> scored => scored.of(factor),
        InsufficientData() => null,
      };

  BaselineBuilding? get building {
    final waiting = [
      for (final input in [hrv, restingHeartRate])
        if (input.baseline case final BaselineBuilding b) b,
    ];
    if (waiting.isEmpty) return null;
    return waiting.reduce((a, b) => a.daysCollected <= b.daysCollected ? a : b);
  }

  int? get baselineNights {
    final days = [
      for (final input in [hrv, restingHeartRate])
        if (input.baseline case BaselineReady(:final days)) days,
    ];
    if (days.isEmpty) return null;
    return days.reduce((a, b) => a < b ? a : b);
  }
}
