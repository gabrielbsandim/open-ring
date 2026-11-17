import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/goals/application/goal_ender.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';

import '../goal_fixtures.dart';

final class _Failing implements GoalStore {
  new(this.inner, {required this.failRead});

  final InMemoryGoalStore inner;
  final bool failRead;

  @override
  Future<Goal?> active() async {
    if (failRead) throw StateError('the goal was not read');
    return await inner.active();
  }

  @override
  Future<bool> end(
    int goalId, {
    required LocalDate on,
    required GoalEndReason reason,
  }) async => throw StateError('the goal was not written');

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final failRead in [true, false]) {
    test('a store that throws on ${failRead ? 'read' : 'write'} is refused, '
        'not thrown', () async {
      final memory = InMemoryGoalStore();
      final setup = await setupGoals(
        draft: goalDraft(),
        store: memory,
        readStore: _Failing(memory, failRead: failRead),
        extraOverrides: [
          demoModeStoreProvider.overrideWithValue(InMemoryDemoModeStore()),
        ],
      );
      setup.container.listen(demoModeProvider, (_, _) {});
      final revision = setup.revision;

      final outcome = await setup.container
          .read(goalEnderProvider.notifier)
          .end(GoalEndReason.person, stepGoalBack: 8000);

      expect(outcome, GoalEndOutcome.refused);
      expect((await memory.active())?.phase, isNot(GoalPhase.ended));
      expect(setup.revision, revision);
    });
  }
}
