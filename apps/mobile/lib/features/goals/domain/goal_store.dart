import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_codec.dart';

abstract interface class GoalStore {
  Future<Goal?> active();

  /// Every goal, the newest first.
  Future<List<Goal>> goals();

  /// Null when a goal is already active. A stored goal that can no longer be
  /// read is ended as [GoalEndReason.unreadable] and does not count.
  Future<Goal?> start(GoalDraft draft);

  /// False for [GoalPhase.ended], which only [end] sets, and for a goal that
  /// is unknown or ended.
  Future<bool> setPhase(
    int goalId,
    GoalPhase phase, {
    required LocalDate since,
    LocalDate? until,
  });

  Future<bool> startBlock(
    int goalId, {
    required LocalDate on,
    required double? anchorKg,
  });

  Future<bool> end(
    int goalId, {
    required LocalDate on,
    required GoalEndReason reason,
  });

  /// Written once per Monday: false when the week exists, when [monday] is
  /// not a Monday, and when the goal is unknown or ended. Throws an
  /// [ArgumentError] for a Monday when [inputs] hold a number that is not
  /// finite.
  Future<bool> addWeek(
    int goalId, {
    required LocalDate monday,
    required ReviewInputs inputs,
    required Review review,
  });

  /// False unless the week waits for an answer on an active goal. Accepting
  /// puts the proposed change in force.
  Future<bool> answer(int goalId, LocalDate monday, WeekAnswer answer);

  /// The reviewed weeks of a goal, the oldest first.
  Future<List<GoalWeek>> weeks(int goalId);

  Future<void> addScreening(GoalScreening screening);

  /// The newest first.
  Future<List<GoalScreening>> screenings();

  /// The rows of goals, weeks and screenings together.
  Future<int> count();

  Future<int> clear();
}

final class InMemoryGoalStore implements GoalStore {
  final _goals = <int, Goal>{};
  final _weeks = <GoalWeek>[];
  final _screenings = <GoalScreening>[];
  var _lastId = 0;

  @override
  Future<Goal?> active() async => _activeGoal;

  @override
  Future<List<Goal>> goals() async => _goals.values.toList().reversed.toList();

  @override
  Future<Goal?> start(GoalDraft draft) async {
    if (_activeGoal != null) return null;
    _lastId += 1;
    return _goals[_lastId] = Goal.started(_lastId, draft);
  }

  @override
  Future<bool> setPhase(
    int goalId,
    GoalPhase phase, {
    required LocalDate since,
    LocalDate? until,
  }) async {
    if (phase == GoalPhase.ended) return false;
    return _change(
      goalId,
      (goal) => goal.inPhase(phase, since: since, until: until),
    );
  }

  @override
  Future<bool> startBlock(
    int goalId, {
    required LocalDate on,
    required double? anchorKg,
  }) async =>
      _change(goalId, (goal) => goal.inBlock(on: on, anchorKg: anchorKg));

  @override
  Future<bool> end(
    int goalId, {
    required LocalDate on,
    required GoalEndReason reason,
  }) async => _change(goalId, (goal) => goal.endedBy(reason, on: on));

  @override
  Future<bool> addWeek(
    int goalId, {
    required LocalDate monday,
    required ReviewInputs inputs,
    required Review review,
  }) async {
    if (mondayOf(monday) != monday) return false;
    encodeReviewInputs(inputs);
    if (_activeWith(goalId) == null) return false;
    if (_weekIndex(goalId, monday) >= 0) return false;
    _weeks.add(
      GoalWeek(
        goalId: goalId,
        monday: monday,
        inputs: inputs,
        rule: review.rule,
        action: review.action,
        change: review.change,
        answer: null,
      ),
    );
    return true;
  }

  @override
  Future<bool> answer(int goalId, LocalDate monday, WeekAnswer answer) async {
    final goal = _activeWith(goalId);
    final index = _weekIndex(goalId, monday);
    if (goal == null || index < 0) return false;
    final week = _weeks[index];
    final change = week.change;
    if (change == null || week.answer != null) return false;
    _weeks[index] = week.answered(answer);
    if (answer == WeekAnswer.accepted) {
      _goals[goalId] = goal.withLevers(applyLeverChange(goal.levers, change));
    }
    return true;
  }

  @override
  Future<List<GoalWeek>> weeks(int goalId) async => [
    for (final week in _weeks)
      if (week.goalId == goalId) week,
  ]..sort((a, b) => a.monday.compareTo(b.monday));

  @override
  Future<void> addScreening(GoalScreening screening) async =>
      _screenings.add(screening);

  @override
  Future<List<GoalScreening>> screenings() async {
    final newestFirst = _screenings.reversed.toList();
    return [
      for (final (_, screening)
          in (newestFirst.indexed.toList()..sort(_newestFirst)))
        screening,
    ];
  }

  @override
  Future<int> count() async =>
      _goals.length + _weeks.length + _screenings.length;

  @override
  Future<int> clear() async {
    final removed = await count();
    _goals.clear();
    _weeks.clear();
    _screenings.clear();
    return removed;
  }

  Goal? get _activeGoal =>
      _goals.values.where((goal) => goal.active).lastOrNull;

  Goal? _activeWith(int goalId) {
    final goal = _goals[goalId];
    if (goal == null || !goal.active) return null;
    return goal;
  }

  bool _change(int goalId, Goal Function(Goal goal) next) {
    final goal = _activeWith(goalId);
    if (goal == null) return false;
    _goals[goalId] = next(goal);
    return true;
  }

  int _weekIndex(int goalId, LocalDate monday) => _weeks.indexWhere(
    (week) => week.goalId == goalId && week.monday == monday,
  );
}

int _newestFirst((int, GoalScreening) a, (int, GoalScreening) b) {
  final byDate = b.$2.on.compareTo(a.$2.on);
  return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
}
