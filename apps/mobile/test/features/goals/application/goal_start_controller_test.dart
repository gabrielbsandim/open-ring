import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

import '../goal_draft_fixture.dart';
import '../goal_fixtures.dart';
import '../goal_picker_harness.dart';

void main() {
  group('3. startWithoutWeight', () {
    test('Get fitter leaves one goal with no levers and bumps once', () async {
      final setup = await setupGoals();

      final started = await setup.container
          .read(goalStartControllerProvider)
          .startWithoutWeight(GoalKind.getFitter);

      final goals = await setup.store.goals();
      expect(started, isNotNull);
      expect(goals, hasLength(1));
      expect(goals.single.kind, GoalKind.getFitter);
      expect(goals.single.levers, isEmpty);
      expect(goals.single.pace, isNull);
      expect(goals.single.anchorKg, isNull);
      expect(goals.single.referenceKg, isNull);
      expect(goals.single.startedOn, goalDay(12, 7));
      expect(setup.revision, 1);
    });

    test('Sleep better starts the same way', () async {
      final setup = await setupGoals();

      await setup.container
          .read(goalStartControllerProvider)
          .startWithoutWeight(GoalKind.sleepBetter);

      final goals = await setup.store.goals();
      expect(goals.single.kind, GoalKind.sleepBetter);
      expect(goals.single.levers, isEmpty);
      expect(setup.revision, 1);
    });

    test('Lose fat throws ArgumentError and writes nothing', () async {
      final setup = await setupGoals();

      await expectLater(
        setup.container
            .read(goalStartControllerProvider)
            .startWithoutWeight(GoalKind.loseFat),
        throwsArgumentError,
      );

      expect(await setup.store.goals(), isEmpty);
      expect(setup.revision, 0);
    });

    test('Goals off returns null and writes 0 rows', () async {
      final setup = await setupGoals(modules: const {ModuleId.body});

      final started = await setup.container
          .read(goalStartControllerProvider)
          .startWithoutWeight(GoalKind.getFitter);

      expect(started, isNull);
      expect(await setup.store.goals(), isEmpty);
      expect(setup.revision, 0);
    });

    test('an active goal makes it return null without a bump', () async {
      final setup = await setupGoals(draft: draftD);

      final started = await setup.container
          .read(goalStartControllerProvider)
          .startWithoutWeight(GoalKind.getFitter);

      expect(started, isNull);
      expect(await setup.store.goals(), hasLength(1));
      expect(setup.revision, 0);
    });

    test('a store error is rethrown and bumps nothing', () async {
      final memory = InMemoryGoalStore();
      final setup = await setupGoals(
        store: memory,
        readStore: ProbeGoalStore(memory, startError: StateError('disk full')),
      );

      await expectLater(
        setup.container
            .read(goalStartControllerProvider)
            .startWithoutWeight(GoalKind.getFitter),
        throwsStateError,
      );

      expect(await memory.goals(), isEmpty);
      expect(setup.revision, 0);
    });

    test(
      'a start that ends after the container is gone does not throw',
      () async {
        final memory = InMemoryGoalStore();
        final gate = Completer<void>();
        final setup = await setupGoals(
          store: memory,
          readStore: ProbeGoalStore(memory, gate: gate),
        );

        final pending = setup.container
            .read(goalStartControllerProvider)
            .startWithoutWeight(GoalKind.getFitter);
        setup.container.dispose();
        gate.complete();

        await expectLater(pending, completes);
      },
    );
  });
}
