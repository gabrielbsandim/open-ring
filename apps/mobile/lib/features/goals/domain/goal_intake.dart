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
