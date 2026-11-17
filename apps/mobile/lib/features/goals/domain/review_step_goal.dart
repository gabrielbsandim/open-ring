import 'package:metrics/metrics.dart';

/// The profile step goal an accepted change puts in force, or null when it
/// leaves the profile alone. The plan only ever raises a goal the person set.
int? stepGoalAfterAccept(LeverChange change, {required int profileGoal}) {
  if (change.kind != LeverKind.steps) return null;
  final to = change.to;
  if (to == null || to <= profileGoal) return null;
  return to;
}
