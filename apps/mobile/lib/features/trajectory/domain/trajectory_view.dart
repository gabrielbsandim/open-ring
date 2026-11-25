import 'package:metrics/metrics.dart';

enum TrajectoryRefusal { underage, pregnancy, noHeight }

/// What the Trajectory card can show today, exactly one state at a time.
sealed class TrajectoryView {
  const new();
}

final class TrajectoryOff extends TrajectoryView {
  const new();
}

final class TrajectoryRefused extends TrajectoryView {
  const new(this.reason);

  final TrajectoryRefusal reason;
}

/// A null [rate] means there is no weigh-in yet.
final class TrajectoryBuilding extends TrajectoryView {
  const new(this.rate);

  final WeightRateBuilding? rate;
}

final class TrajectoryGuard extends TrajectoryView {
  const new(this.loss);

  final LossRate loss;
}

final class TrajectoryReady extends TrajectoryView {
  const new({
    required this.asOf,
    required this.trendKg,
    required this.rate,
    required this.noiseKg,
    required this.firm,
    required this.band,
  });

  final LocalDate asOf;
  final double trendKg;
  final WeightRateReady rate;
  final double noiseKg;
  final ScenarioBand firm;
  final ScenarioBand band;
}

final class TrajectoryError extends TrajectoryView {
  const new(this.error);

  final Object error;
}
