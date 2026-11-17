import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';

const goalScreeningQuestions = 5;

/// Why a weight goal is not offered, in the order the checks run.
enum IntakeBlock {
  bodyOff,
  softMode,
  ageMissing,
  under18,
  heightMissing,
  bmiUnderFloor,
}

enum IntakeNext { screening, setup }

/// The age is the youngest the birth year allows.
typedef IntakeFacts = ({
  bool bodyOn,
  int? age,
  double? heightCm,
  double? trendKg,
  bool? softMode,
});

// Soft mode null means never asked, which is not a no: only true blocks.
IntakeBlock? weightGoalBlock(IntakeFacts facts) {
  if (!facts.bodyOn) return IntakeBlock.bodyOff;
  if (facts.softMode ?? false) return IntakeBlock.softMode;
  final age = facts.age;
  if (age == null) return IntakeBlock.ageMissing;
  if (age < goalMinAge) return IntakeBlock.under18;
  final heightCm = facts.heightCm;
  if (heightCm == null) return IntakeBlock.heightMissing;
  final trendKg = facts.trendKg;
  if (trendKg == null) return null;
  if (bmi(trendKg, heightCm) < bmiFloor) return IntakeBlock.bmiUnderFloor;
  return null;
}

// The questions are asked once: a stored no goes straight to the setup.
IntakeNext weightGoalNext(IntakeFacts facts) =>
    facts.softMode == null ? IntakeNext.screening : IntakeNext.setup;

/// The answer of the newest screening that asked the five questions.
bool? newestSoftMode(List<GoalScreening> newestFirst) =>
    newestFirst.map((screening) => screening.softMode).nonNulls.firstOrNull;

/// What Continue on the picker leads to for the chosen goal.
sealed class PickStep {
  const new();
}

final class PickNoGoal extends PickStep {
  const new();
}

final class PickStart extends PickStep {
  const new(this.kind);

  final GoalKind kind;
}

final class PickBlocked extends PickStep {
  const new(this.block);

  final IntakeBlock block;
}

final class PickWeight extends PickStep {
  const new(this.next);

  final IntakeNext next;
}

PickStep pickStep(GoalKind? choice, IntakeFacts facts) {
  if (choice == null) return const PickNoGoal();
  if (choice != GoalKind.loseFat) return PickStart(choice);
  final block = weightGoalBlock(facts);
  if (block != null) return PickBlocked(block);
  return PickWeight(weightGoalNext(facts));
}

/// The first year in which every birth date of [birthYear] is 18 or older.
int weightGoalsOpenYear(int birthYear) => birthYear + goalMinAge + 1;

// A BMI under the floor must never read as the floor once rounded.
double shownBmi(double bmi) {
  final tenths = (bmi * 10).round();
  final floorTenths = (bmiFloor * 10).round();
  if (bmi < bmiFloor && tenths >= floorTenths) return (floorTenths - 1) / 10;
  return tenths / 10;
}
