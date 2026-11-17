import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

import '../goal_fixtures.dart';

GoalScreening _row(int day, {bool? softMode, bool? pregnant}) => GoalScreening(
  on: goalDay(12, day),
  softMode: softMode,
  pregnantOrBreastfeeding: pregnant,
);

IntakeFacts _facts(bool? softMode) =>
    (bodyOn: true, age: 30, heightCm: 178, trendKg: 70, softMode: softMode);

void main() {
  group('1. leaving after a stored yes', () {
    test(
      'adds one row dated today with soft mode false and returns true',
      () async {
        final setup = await setupGoals();
        await setup.store.addScreening(_row(1, softMode: true));

        final left = await setup.container
            .read(softModeControllerProvider)
            .leave();

        final rows = await setup.store.screenings();
        expect(left, isTrue);
        expect(rows, hasLength(2));
        expect(rows.first.on, goalDay(12, 7));
        expect(rows.first.softMode, isFalse);
        expect(rows.first.pregnantOrBreastfeeding, isNull);
      },
    );

    test(
      'the newest soft answer becomes false and the next step is setup',
      () async {
        final setup = await setupGoals();
        await setup.store.addScreening(_row(1, softMode: true));

        await setup.container.read(softModeControllerProvider).leave();

        final soft = newestSoftMode(await setup.store.screenings());
        expect(soft, isFalse);
        expect(weightGoalNext(_facts(soft)), IntakeNext.setup);
        expect(weightGoalBlock(_facts(soft)), isNull);
      },
    );

    test(
      'bumps the data revision once and the provider answers false',
      () async {
        final setup = await setupGoals();
        await setup.store.addScreening(_row(1, softMode: true));
        expect(await setup.container.read(softModeProvider.future), isTrue);

        await setup.container.read(softModeControllerProvider).leave();

        expect(setup.revision, 1);
        expect(await setup.container.read(softModeProvider.future), isFalse);
      },
    );

    test('keeps the earlier yes in the history', () async {
      final setup = await setupGoals();
      await setup.store.addScreening(_row(1, softMode: true));

      await setup.container.read(softModeControllerProvider).leave();

      final rows = await setup.store.screenings();
      expect(rows.last.softMode, isTrue);
      expect(rows.last.on, goalDay(12, 1));
    });
  });

  group('2. leaving when there is nothing to leave', () {
    test('a newest answer of false writes nothing and returns false', () async {
      final setup = await setupGoals();
      await setup.store.addScreening(_row(1, softMode: false));

      final left = await setup.container
          .read(softModeControllerProvider)
          .leave();

      expect(left, isFalse);
      expect(await setup.store.screenings(), hasLength(1));
      expect(setup.revision, 0);
    });

    test('no screening at all writes nothing and returns false', () async {
      final setup = await setupGoals();

      final left = await setup.container
          .read(softModeControllerProvider)
          .leave();

      expect(left, isFalse);
      expect(await setup.store.screenings(), isEmpty);
      expect(setup.revision, 0);
    });

    test('Goals off writes nothing and returns false', () async {
      final setup = await setupGoals(modules: const {ModuleId.body});
      await setup.store.addScreening(_row(1, softMode: true));

      final left = await setup.container
          .read(softModeControllerProvider)
          .leave();

      expect(left, isFalse);
      expect(await setup.store.screenings(), hasLength(1));
      expect(setup.revision, 0);
    });

    test('demo mode writes nothing and returns false', () async {
      final setup = await setupGoals(
        extraOverrides: [
          demoModeStoreProvider.overrideWithValue(
            InMemoryDemoModeStore(enabled: true),
          ),
        ],
      );
      await setup.store.addScreening(_row(1, softMode: true));

      final left = await setup.container
          .read(softModeControllerProvider)
          .leave();

      expect(left, isFalse);
      expect(await setup.store.screenings(), hasLength(1));
      expect(setup.revision, 0);
    });

    test('a stale cached yes does not write once the store says no', () async {
      final setup = await setupGoals();
      await setup.store.addScreening(_row(1, softMode: true));
      expect(await setup.container.read(softModeProvider.future), isTrue);
      await setup.store.addScreening(_row(2, softMode: false));

      final left = await setup.container
          .read(softModeControllerProvider)
          .leave();

      expect(left, isFalse);
      expect(await setup.store.screenings(), hasLength(2));
    });
  });

  group('3. a pregnancy-only row above a yes', () {
    test(
      'leave still writes and the newest soft answer becomes false',
      () async {
        final setup = await setupGoals();
        await setup.store.addScreening(_row(1, softMode: true));
        await setup.store.addScreening(_row(2, pregnant: true));

        final left = await setup.container
            .read(softModeControllerProvider)
            .leave();

        final rows = await setup.store.screenings();
        expect(left, isTrue);
        expect(rows, hasLength(3));
        expect(rows.first.softMode, isFalse);
        expect(rows.first.pregnantOrBreastfeeding, isNull);
        expect(newestSoftMode(rows), isFalse);
      },
    );
  });
}
