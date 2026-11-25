import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/review_inputs.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';

/// The band as it stood on the Monday of [today]'s week, from the weigh-ins up
/// to that Monday only. Null unless that Monday was ready and not guarded.
TrajectoryProjection? mondayProjection({
  required LocalDate today,
  required List<DailyValue> daily,
  required DateTime createdAt,
}) {
  final monday = mondayOf(today);
  final snapshot = weightSnapshot(daily: daily, asOf: monday);
  final rate = snapshot.rate;
  final trendKg = snapshot.trendKg;
  if (rate is! WeightRateReady || trendKg == null) return null;
  if (fastLossGuard(lossRate(rate, trendKg))) return null;
  final past = [
    for (final day in daily)
      if (day.date.compareTo(monday) <= 0) day,
  ];
  final band = weightScenario(
    trendKg,
    rate,
    weightNoise(past),
    trajectoryFirmDays,
  );
  return TrajectoryProjection(
    monday: monday,
    trendKg: trendKg,
    rateKgPerWeek: rate.perWeek,
    lowKg: band.low,
    midKg: band.mid,
    highKg: band.high,
    createdAt: createdAt,
  );
}
