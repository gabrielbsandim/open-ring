import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
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

typedef ShownReference = ({double low, double high, double step});

/// The reference range in the person's unit: whole pounds rounded inward,
/// so every value shown converts back inside the bounds.
ShownReference shownReference(ReferenceBounds bounds, UnitSystem system) =>
    switch (system) {
      UnitSystem.metric => (
        low: bounds.minKg,
        high: bounds.maxKg,
        step: goalReferenceStepKg,
      ),
      UnitSystem.imperial => (
        low: (ImperialUnits.pounds(bounds.minKg) - 1e-9).ceilToDouble(),
        high: (ImperialUnits.pounds(bounds.maxKg) + 1e-9).floorToDouble(),
        step: 1,
      ),
    };

double referenceKgFor(double shown, UnitSystem system, ReferenceBounds bounds) {
  final kg = switch (system) {
    UnitSystem.metric => shown,
    UnitSystem.imperial => ImperialUnits.kilograms(shown),
  };
  return kg.clamp(bounds.minKg, bounds.maxKg);
}

/// The value the stepper shows for a weight kept in kilograms: on the step
/// of the unit and inside the range, which is also the value sent.
double shownValueFor(double kg, ShownReference shown, UnitSystem system) {
  final inUnit = switch (system) {
    UnitSystem.metric => kg,
    UnitSystem.imperial => ImperialUnits.pounds(kg),
  };
  final onStep = (inUnit / shown.step).roundToDouble() * shown.step;
  return onStep.clamp(shown.low, shown.high);
}
