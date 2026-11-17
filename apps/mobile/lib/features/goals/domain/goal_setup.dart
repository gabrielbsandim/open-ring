import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

enum SetupOutcome { started, pregnancy, alreadyActive, notAllowed }

typedef ReferenceBounds = ({double minKg, double maxKg});

/// Whether the setup asks about pregnancy and breastfeeding: always unless
/// the profile says male, and again whenever the newest answer was a yes.
bool asksPregnancy(Sex? sex, List<GoalScreening> newestFirst) =>
    sex != Sex.male || newestPregnancy(newestFirst) == true;

bool? newestPregnancy(List<GoalScreening> newestFirst) => newestFirst
    .map((screening) => screening.pregnantOrBreastfeeding)
    .nonNulls
    .firstOrNull;

/// The reference weights a loss goal may name: any weight from the BMI floor
/// for the height up to the trend rounded down to [goalReferenceStepKg]. Null
/// when that top is not above the floor.
ReferenceBounds? referenceBounds({
  required double heightCm,
  required double trendKg,
}) {
  final minKg = referenceFloorKg(heightCm);
  final maxKg = (trendKg / goalReferenceStepKg).floor() * goalReferenceStepKg;
  if (maxKg <= minKg) return null;
  return (minKg: minKg, maxKg: maxKg);
}
