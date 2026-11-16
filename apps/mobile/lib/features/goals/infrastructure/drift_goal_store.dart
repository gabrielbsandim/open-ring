import 'package:drift/drift.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_codec.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';

final class DriftGoalStore implements GoalStore {
  new(this._db);

  final AppDatabase _db;

  @override
  Future<Goal?> active() async =>
      (await goals()).where((goal) => goal.active).firstOrNull;

  @override
  Future<List<Goal>> goals() async {
    final rows = await (_db.select(
      _db.goals,
    )..orderBy([(row) => OrderingTerm.desc(row.id)])).get();
    return [for (final row in rows) ?_goal(row)];
  }

  // An open row that no longer decodes is ended and kept: no read returns its
  // id, so left open it would block every later goal.
  @override
  Future<Goal?> start(GoalDraft draft) => _db.transaction(() async {
    final open = await (_db.select(_db.goals)..where(_open)).get();
    if (open.any((row) => _goal(row) != null)) return null;
    for (final row in open) {
      await _write(
        row.id,
        GoalsCompanion(
          phase: Value(GoalPhase.ended.name),
          phaseSince: Value(draft.startedOn.iso),
          phaseUntil: const Value(null),
          endedOn: Value(draft.startedOn.iso),
          endReason: Value(GoalEndReason.unreadable.name),
        ),
      );
    }
    final id = await _db
        .into(_db.goals)
        .insert(
          GoalsCompanion.insert(
            kind: draft.kind.name,
            pace: Value(draft.pace?.name),
            startedOn: draft.startedOn.iso,
            anchorKg: Value(draft.anchorKg),
            referenceKg: Value(draft.referenceKg),
            blockStartedOn: draft.startedOn.iso,
            blockAnchorKg: Value(draft.anchorKg),
            phase: GoalPhase.block.name,
            phaseSince: draft.startedOn.iso,
            levers: encodeLevers(draft.levers),
          ),
        );
    return Goal.started(id, draft);
  });

  @override
  Future<bool> setPhase(
    int goalId,
    GoalPhase phase, {
    required LocalDate since,
    LocalDate? until,
  }) async {
    if (phase == GoalPhase.ended) return false;
    return await _write(
      goalId,
      GoalsCompanion(
        phase: Value(phase.name),
        phaseSince: Value(since.iso),
        phaseUntil: Value(until?.iso),
      ),
    );
  }

  @override
  Future<bool> startBlock(
    int goalId, {
    required LocalDate on,
    required double? anchorKg,
  }) => _write(
    goalId,
    GoalsCompanion(
      blockStartedOn: Value(on.iso),
      blockAnchorKg: Value(anchorKg),
      phase: Value(GoalPhase.block.name),
      phaseSince: Value(on.iso),
      phaseUntil: const Value(null),
    ),
  );

  @override
  Future<bool> end(
    int goalId, {
    required LocalDate on,
    required GoalEndReason reason,
  }) => _write(
    goalId,
    GoalsCompanion(
      phase: Value(GoalPhase.ended.name),
      phaseSince: Value(on.iso),
      phaseUntil: const Value(null),
      endedOn: Value(on.iso),
      endReason: Value(reason.name),
    ),
  );

  @override
  Future<bool> addWeek(
    int goalId, {
    required LocalDate monday,
    required ReviewInputs inputs,
    required Review review,
  }) async {
    if (mondayOf(monday) != monday) return false;
    final change = review.change;
    final row = GoalWeeksCompanion.insert(
      goalId: goalId,
      monday: monday.iso,
      inputs: encodeReviewInputs(inputs),
      rule: review.rule.name,
      action: review.action.name,
      change: Value(change == null ? null : encodeLeverChange(change)),
    );
    return await _db.transaction(() async {
      if (await _openRow(goalId) == null) return false;
      if (await _weekRow(goalId, monday) != null) return false;
      await _db.into(_db.goalWeeks).insert(row);
      return true;
    });
  }

  @override
  Future<bool> answer(int goalId, LocalDate monday, WeekAnswer answer) =>
      _db.transaction(() async {
        final goalRow = await _openRow(goalId);
        final weekRow = await _weekRow(goalId, monday);
        if (goalRow == null || weekRow == null) return false;
        final goal = _goal(goalRow);
        final week = _week(weekRow);
        final change = week?.change;
        if (goal == null || week == null || change == null) return false;
        if (week.answer != null) return false;
        await (_db.update(_db.goalWeeks)..where(
              (row) =>
                  row.goalId.equals(goalId) & row.monday.equals(monday.iso),
            ))
            .write(GoalWeeksCompanion(answer: Value(answer.name)));
        if (answer != WeekAnswer.accepted) return true;
        return await _write(
          goalId,
          GoalsCompanion(
            levers: Value(encodeLevers(applyLeverChange(goal.levers, change))),
          ),
        );
      });

  @override
  Future<List<GoalWeek>> weeks(int goalId) async {
    final rows =
        await (_db.select(_db.goalWeeks)
              ..where((row) => row.goalId.equals(goalId))
              ..orderBy([(row) => OrderingTerm.asc(row.monday)]))
            .get();
    return [for (final row in rows) ?_week(row)];
  }

  @override
  Future<void> addScreening(GoalScreening screening) => _db
      .into(_db.goalScreenings)
      .insert(
        GoalScreeningsCompanion.insert(
          askedOn: screening.on.iso,
          softMode: Value(screening.softMode),
          pregnantOrBreastfeeding: Value(screening.pregnantOrBreastfeeding),
        ),
      );

  @override
  Future<List<GoalScreening>> screenings() async {
    final rows =
        await (_db.select(_db.goalScreenings)..orderBy([
              (row) => OrderingTerm.desc(row.askedOn),
              (row) => OrderingTerm.desc(row.id),
            ]))
            .get();
    return [
      for (final row in rows)
        if (LocalDate.tryParse(row.askedOn) case final on?)
          GoalScreening(
            on: on,
            softMode: row.softMode,
            pregnantOrBreastfeeding: row.pregnantOrBreastfeeding,
          ),
    ];
  }

  @override
  Future<int> count() async {
    final goals = await _db.goals.count().getSingle();
    final weeks = await _db.goalWeeks.count().getSingle();
    final screenings = await _db.goalScreenings.count().getSingle();
    return goals + weeks + screenings;
  }

  @override
  Future<int> clear() => _db.transaction(() async {
    final removed = await count();
    await _db.delete(_db.goalWeeks).go();
    await _db.delete(_db.goals).go();
    await _db.delete(_db.goalScreenings).go();
    return removed;
  });

  Expression<bool> _open($GoalsTable row) =>
      row.phase.equals(GoalPhase.ended.name).not();

  Future<GoalRow?> _openRow(int goalId) => (_db.select(
    _db.goals,
  )..where((row) => row.id.equals(goalId) & _open(row))).getSingleOrNull();

  Future<GoalWeekRow?> _weekRow(int goalId, LocalDate monday) =>
      (_db.select(_db.goalWeeks)..where(
            (row) => row.goalId.equals(goalId) & row.monday.equals(monday.iso),
          ))
          .getSingleOrNull();

  Future<bool> _write(int goalId, GoalsCompanion values) async {
    final changed = await (_db.update(
      _db.goals,
    )..where((row) => row.id.equals(goalId) & _open(row))).write(values);
    return changed > 0;
  }
}

Goal? _goal(GoalRow row) {
  final kind = _named(GoalKind.values, row.kind);
  final startedOn = LocalDate.tryParse(row.startedOn);
  final blockStartedOn = LocalDate.tryParse(row.blockStartedOn);
  final phase = _named(GoalPhase.values, row.phase);
  final phaseSince = LocalDate.tryParse(row.phaseSince);
  final levers = decodeLevers(row.levers);
  if (kind == null || startedOn == null || blockStartedOn == null) return null;
  if (phase == null || phaseSince == null || levers == null) return null;
  return Goal(
    id: row.id,
    kind: kind,
    pace: _named(GoalPace.values, row.pace),
    startedOn: startedOn,
    anchorKg: row.anchorKg,
    referenceKg: row.referenceKg,
    blockStartedOn: blockStartedOn,
    blockAnchorKg: row.blockAnchorKg,
    phase: phase,
    phaseSince: phaseSince,
    phaseUntil: LocalDate.tryParse(row.phaseUntil),
    levers: levers,
    endedOn: LocalDate.tryParse(row.endedOn),
    endReason: _named(GoalEndReason.values, row.endReason),
  );
}

GoalWeek? _week(GoalWeekRow row) {
  final monday = LocalDate.tryParse(row.monday);
  final inputs = decodeReviewInputs(row.inputs);
  final rule = _named(ReviewRule.values, row.rule);
  final action = _named(ReviewAction.values, row.action);
  final stored = row.change;
  final change = stored == null ? null : decodeLeverChange(stored);
  if (monday == null || inputs == null || rule == null) return null;
  if (action == null || (stored != null && change == null)) return null;
  return GoalWeek(
    goalId: row.goalId,
    monday: monday,
    inputs: inputs,
    rule: rule,
    action: action,
    change: change,
    answer: _named(WeekAnswer.values, row.answer),
  );
}

T? _named<T extends Enum>(List<T> values, String? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
