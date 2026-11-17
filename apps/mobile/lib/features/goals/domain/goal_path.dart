import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/review_inputs.dart';

/// The weight path of a goal as it stood on [on].
final class GoalPath {
  const new({
    required this.on,
    required this.block,
    required this.startKg,
    required this.trendKg,
    required this.referenceKg,
    required this.weightRate,
    required this.rate,
    required this.targetPercent,
    required this.capPercent,
    required this.state,
    required this.arrival,
  });

  final LocalDate on;

  /// The block under way, null when the goal kept no anchor weight.
  final GoalBlock? block;
  final double? startKg;

  /// Null when the newest weigh-in is a whole rate window old.
  final double? trendKg;
  final double? referenceKg;
  final WeightRate? weightRate;
  final LossRate? rate;
  final double targetPercent;
  final double capPercent;
  final PathState state;
  final ArrivalRange? arrival;

  bool get overTheCap {
    final current = rate;
    return current != null && overCap(current, capPercent);
  }
}

/// The day the path is read on. The review reads the week up to the Sunday
/// before its Monday, so the path holds still between reviews.
LocalDate goalPathDay(Goal goal, LocalDate today) {
  // A goal with no lever waits for today's rate to start its block, so the
  // base phase reads today.
  if (goal.levers.isEmpty) return today;
  final sunday = mondayOf(today).addDays(-1);
  if (sunday.compareTo(goal.blockStartedOn) < 0) return goal.blockStartedOn;
  return sunday;
}

GoalPath goalPath({
  required Goal goal,
  required WeightSnapshot snapshot,
  required double? heightCm,
  required LocalDate on,
}) {
  final reading = weightReading(
    kind: goal.kind,
    pace: goal.pace,
    bodyOn: true,
    rate: snapshot.rate,
    trendKg: snapshot.trendKg,
    heightCm: heightCm,
  );
  final anchor = goal.blockAnchorKg;
  final block = anchor == null
      ? null
      : goalBlock(
          startKg: anchor,
          percentPerWeek: reading.targetPercent,
          start: goal.blockStartedOn,
        );
  final rate = reading.rate;
  final trend = snapshot.trendKg;
  final reference = goal.referenceKg;
  return GoalPath(
    on: on,
    block: block,
    startKg: anchor,
    trendKg: trend,
    referenceKg: reference,
    weightRate: snapshot.rate,
    rate: rate,
    targetPercent: reading.targetPercent,
    capPercent: reading.capPercent,
    state: pathState(
      rate,
      targetPercent: reading.targetPercent,
      capPercent: reading.capPercent,
    ),
    arrival: rate == null || trend == null || reference == null || block == null
        ? null
        : arrivalRange(
            trendKg: trend,
            referenceKg: reference,
            rate: rate,
            today: on,
            block: block,
          ),
  );
}
