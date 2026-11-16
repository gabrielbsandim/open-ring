import 'package:metrics/metrics.dart';

typedef StepGoalChange = ({LocalDate from, int steps});

// Dated before any day the app can score, so it reads as the goal of every
// day that came before the first change.
const stepGoalBaselineDate = LocalDate(1970, 1, 1);

/// The step goal in force on [date]: the last of [changes] (ascending by
/// date) on or before it, or [current] when none is.
int stepGoalOn(
  LocalDate date, {
  required List<StepGoalChange> changes,
  required int current,
}) {
  var goal = current;
  for (final change in changes) {
    if (change.from.compareTo(date) > 0) break;
    goal = change.steps;
  }
  return goal;
}

abstract interface class StepGoalHistory {
  Future<List<StepGoalChange>> changes();

  /// Stores [steps] as the goal from [on]. The first call also stores
  /// [previous] as the goal of every earlier day.
  Future<void> record({
    required LocalDate on,
    required int steps,
    required int previous,
  });
}

final class InMemoryStepGoalHistory implements StepGoalHistory {
  final Map<LocalDate, int> _steps = {};

  @override
  Future<List<StepGoalChange>> changes() async {
    final dates = _steps.keys.toList()..sort((a, b) => a.compareTo(b));
    return [for (final date in dates) (from: date, steps: _steps[date]!)];
  }

  @override
  Future<void> record({
    required LocalDate on,
    required int steps,
    required int previous,
  }) async {
    if (_steps.isEmpty) _steps[stepGoalBaselineDate] = previous;
    _steps[on] = steps;
  }
}
