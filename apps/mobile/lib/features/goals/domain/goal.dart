import 'package:metrics/metrics.dart';

enum GoalPhase { block, maintenance, paused, ended }

// unreadable closes a stored goal this build can no longer read, so it cannot
// keep a new one from starting.
enum GoalEndReason { person, switched, protection, unreadable }

enum WeekAnswer { accepted, declined }

final class Goal {
  const new({
    required this.id,
    required this.kind,
    required this.pace,
    required this.startedOn,
    required this.anchorKg,
    required this.referenceKg,
    required this.blockStartedOn,
    required this.blockAnchorKg,
    required this.phase,
    required this.phaseSince,
    required this.phaseUntil,
    required this.levers,
    required this.endedOn,
    required this.endReason,
  });

  factory started(int id, GoalDraft draft) => Goal(
    id: id,
    kind: draft.kind,
    pace: draft.pace,
    startedOn: draft.startedOn,
    anchorKg: draft.anchorKg,
    referenceKg: draft.referenceKg,
    blockStartedOn: draft.startedOn,
    blockAnchorKg: draft.anchorKg,
    phase: GoalPhase.block,
    phaseSince: draft.startedOn,
    phaseUntil: null,
    levers: draft.levers,
    endedOn: null,
    endReason: null,
  );

  final int id;
  final GoalKind kind;
  final GoalPace? pace;
  final LocalDate startedOn;
  final double? anchorKg;
  final double? referenceKg;
  final LocalDate blockStartedOn;
  final double? blockAnchorKg;
  final GoalPhase phase;
  final LocalDate phaseSince;

  /// The last day of the phase, inclusive.
  final LocalDate? phaseUntil;
  final List<Lever> levers;
  final LocalDate? endedOn;
  final GoalEndReason? endReason;

  bool get active => phase != GoalPhase.ended;

  Goal inPhase(GoalPhase next, {required LocalDate since, LocalDate? until}) =>
      _with(phase: next, phaseSince: since, phaseUntil: until);

  Goal inBlock({required LocalDate on, required double? anchorKg}) => _with(
    blockStartedOn: on,
    blockAnchorKg: anchorKg,
    phase: GoalPhase.block,
    phaseSince: on,
    phaseUntil: null,
  );

  Goal endedBy(GoalEndReason reason, {required LocalDate on}) => _with(
    phase: GoalPhase.ended,
    phaseSince: on,
    phaseUntil: null,
    endedOn: on,
    endReason: reason,
  );

  Goal withLevers(List<Lever> next) => _with(
    phase: phase,
    phaseSince: phaseSince,
    phaseUntil: phaseUntil,
    levers: next,
  );

  Goal _with({
    required GoalPhase phase,
    required LocalDate phaseSince,
    required LocalDate? phaseUntil,
    LocalDate? blockStartedOn,
    double? blockAnchorKg,
    List<Lever>? levers,
    LocalDate? endedOn,
    GoalEndReason? endReason,
  }) => Goal(
    id: id,
    kind: kind,
    pace: pace,
    startedOn: startedOn,
    anchorKg: anchorKg,
    referenceKg: referenceKg,
    blockStartedOn: blockStartedOn ?? this.blockStartedOn,
    blockAnchorKg: blockStartedOn == null ? this.blockAnchorKg : blockAnchorKg,
    phase: phase,
    phaseSince: phaseSince,
    phaseUntil: phaseUntil,
    levers: levers ?? this.levers,
    endedOn: endedOn ?? this.endedOn,
    endReason: endReason ?? this.endReason,
  );
}

final class GoalDraft {
  const new({
    required this.kind,
    required this.pace,
    required this.startedOn,
    required this.anchorKg,
    required this.referenceKg,
    required this.levers,
  });

  final GoalKind kind;
  final GoalPace? pace;
  final LocalDate startedOn;
  final double? anchorKg;
  final double? referenceKg;
  final List<Lever> levers;
}

final class GoalWeek {
  const new({
    required this.goalId,
    required this.monday,
    required this.inputs,
    required this.rule,
    required this.action,
    required this.change,
    required this.answer,
  });

  final int goalId;
  final LocalDate monday;
  final ReviewInputs inputs;
  final ReviewRule rule;
  final ReviewAction action;
  final LeverChange? change;
  final WeekAnswer? answer;

  bool get pending => change != null && answer == null;

  GoalWeek answered(WeekAnswer next) => GoalWeek(
    goalId: goalId,
    monday: monday,
    inputs: inputs,
    rule: rule,
    action: action,
    change: change,
    answer: next,
  );
}

// A null answer means that question was not asked this time.
final class GoalScreening {
  const new({
    required this.on,
    required this.softMode,
    required this.pregnantOrBreastfeeding,
  });

  final LocalDate on;
  final bool? softMode;
  final bool? pregnantOrBreastfeeding;
}
