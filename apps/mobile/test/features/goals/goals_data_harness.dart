import 'dart:async';

import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';

import 'goal_fixtures.dart';

/// A goal store whose clear can wait on [clearGate] or throw [clearFailure],
/// and that counts how many times clear ran. Reads go to [inner].
final class SpyGoalStore implements GoalStore {
  new(this.inner);

  final InMemoryGoalStore inner;
  Object? clearFailure;
  Completer<void>? clearGate;
  int clearCalls = 0;

  @override
  Future<Goal?> active() => inner.active();

  @override
  Future<List<Goal>> goals() => inner.goals();

  @override
  Future<Goal?> start(GoalDraft draft) => inner.start(draft);

  @override
  Future<List<GoalWeek>> weeks(int goalId) => inner.weeks(goalId);

  @override
  Future<void> addScreening(GoalScreening screening) =>
      inner.addScreening(screening);

  @override
  Future<List<GoalScreening>> screenings() => inner.screenings();

  @override
  Future<int> count() => inner.count();

  @override
  Future<int> clear() async {
    clearCalls++;
    await clearGate?.future;
    final failure = clearFailure;
    if (failure != null) throw failure;
    return await inner.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

/// Goal 1 with [weeks] reviewed weeks, then [screenings] screening rows, the
/// newest answering [soft]. With [goal] false only the screenings are stored.
Future<void> seedGoalsData(
  InMemoryGoalStore store, {
  bool goal = true,
  int weeks = 3,
  int screenings = 1,
  bool soft = true,
}) async {
  if (goal) {
    await store.start(goalDraft());
    for (var i = 0; i < weeks; i++) {
      await store.addWeek(
        1,
        monday: goalDay(12, 7).addDays(7 * i),
        inputs: f1,
        review: reviewWeek(f1),
      );
    }
  }
  for (var i = 0; i < screenings; i++) {
    await store.addScreening(
      GoalScreening(
        on: goalDay(12, 1).addDays(i),
        softMode: soft,
        pregnantOrBreastfeeding: null,
      ),
    );
  }
}
