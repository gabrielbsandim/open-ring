import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

import '../goal_fixtures.dart';

final class _FailingScreeningStore implements GoalStore {
  @override
  Future<void> addScreening(GoalScreening screening) =>
      Future.error(StateError('disk full'));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

Override _profile(UserProfile? profile) => userProfileStoreProvider
    .overrideWithValue(InMemoryUserProfileStore(profile));

GoalScreening _row(int day, {bool? softMode, bool? pregnant}) => GoalScreening(
  on: goalDay(12, day),
  softMode: softMode,
  pregnantOrBreastfeeding: pregnant,
);

const _answers = [true, true, false, false, false];

void main() {
  group('7. submit with two yes answers', () {
    test('returns true and writes one row with the result only', () async {
      final setup = await setupGoals();

      final result = await setup.container
          .read(screeningControllerProvider)
          .submit(_answers);

      final rows = await setup.store.screenings();
      expect(result, isTrue);
      expect(rows, hasLength(1));
      expect(rows.single.on, goalDay(12, 7));
      expect(rows.single.softMode, isTrue);
      expect(rows.single.pregnantOrBreastfeeding, isNull);
      expect(await setup.store.goals(), isEmpty);
    });

    test('bumps the data revision once', () async {
      final setup = await setupGoals();

      await setup.container.read(screeningControllerProvider).submit(_answers);

      expect(setup.revision, 1);
    });

    test('the soft mode provider then answers true', () async {
      final setup = await setupGoals();
      expect(await setup.container.read(softModeProvider.future), isNull);

      await setup.container.read(screeningControllerProvider).submit(_answers);

      expect(await setup.container.read(softModeProvider.future), isTrue);
    });
  });

  group('8. the soft mode threshold', () {
    test('one yes stores softMode false', () async {
      final setup = await setupGoals();

      final result = await setup.container
          .read(screeningControllerProvider)
          .submit(const [false, true, false, false, false]);

      final rows = await setup.store.screenings();
      expect(result, isFalse);
      expect(rows.single.softMode, isFalse);
    });

    test('no yes stores softMode false', () async {
      final setup = await setupGoals();

      final result = await setup.container
          .read(screeningControllerProvider)
          .submit(const [false, false, false, false, false]);

      expect(result, isFalse);
      expect((await setup.store.screenings()).single.softMode, isFalse);
    });

    test('five yes stores softMode true', () async {
      final setup = await setupGoals();

      final result = await setup.container
          .read(screeningControllerProvider)
          .submit(const [true, true, true, true, true]);

      expect(result, isTrue);
      expect((await setup.store.screenings()).single.softMode, isTrue);
    });
  });

  group('9. a wrong number of answers', () {
    test('four answers throw ArgumentError and write nothing', () async {
      final setup = await setupGoals();

      await expectLater(
        setup.container.read(screeningControllerProvider).submit(const [
          true,
          true,
          true,
          true,
        ]),
        throwsArgumentError,
      );

      expect(await setup.store.count(), 0);
      expect(setup.revision, 0);
    });

    test('six answers throw ArgumentError and write nothing', () async {
      final setup = await setupGoals();

      await expectLater(
        setup.container.read(screeningControllerProvider).submit(const [
          true,
          true,
          true,
          true,
          true,
          true,
        ]),
        throwsArgumentError,
      );

      expect(await setup.store.count(), 0);
    });

    test('no answers throw ArgumentError', () async {
      final setup = await setupGoals();

      await expectLater(
        setup.container.read(screeningControllerProvider).submit(const []),
        throwsArgumentError,
      );
    });
  });

  group('11. a store that throws', () {
    test('rethrows and does not bump the revision', () async {
      final setup = await setupGoals(readStore: _FailingScreeningStore());

      await expectLater(
        setup.container.read(screeningControllerProvider).submit(_answers),
        throwsA(isA<StateError>()),
      );

      expect(setup.revision, 0);
    });
  });

  group('review focus 3: two taps on Continue', () {
    test('two submits write two rows', () async {
      final setup = await setupGoals();
      final controller = setup.container.read(screeningControllerProvider);

      await controller.submit(_answers);
      await controller.submit(_answers);

      expect(await setup.store.screenings(), hasLength(2));
      expect(setup.revision, 2);
    });
  });

  group('softModeProvider', () {
    test('is null with no screening', () async {
      final setup = await setupGoals();

      expect(await setup.container.read(softModeProvider.future), isNull);
    });

    test('reads the newest row that has a soft mode answer', () async {
      final store = InMemoryGoalStore();
      await store.addScreening(_row(1, softMode: true));
      await store.addScreening(_row(2, pregnant: true));
      final setup = await setupGoals(store: store);

      expect(await setup.container.read(softModeProvider.future), isTrue);
    });

    test('a newer false is not folded under an older true', () async {
      final store = InMemoryGoalStore();
      await store.addScreening(_row(1, softMode: true));
      await store.addScreening(_row(2, softMode: false));
      final setup = await setupGoals(store: store);

      expect(await setup.container.read(softModeProvider.future), isFalse);
    });

    test('stays null when only pregnancy was answered', () async {
      final store = InMemoryGoalStore();
      await store.addScreening(_row(1, pregnant: false));
      final setup = await setupGoals(store: store);

      expect(await setup.container.read(softModeProvider.future), isNull);
    });
  });

  group('intakeFactsProvider', () {
    test('reads Body on, age, height, trend and soft mode', () async {
      final store = InMemoryGoalStore();
      await store.addScreening(_row(1, softMode: true));
      await store.addScreening(_row(2, pregnant: true));
      final setup = await setupGoals(
        store: store,
        profileOverride: _profile(
          const UserProfile(birthYear: 1992, heightCentimeters: 181),
        ),
      );

      final facts = await setup.container.read(intakeFactsProvider.future);

      expect(facts, (
        bodyOn: true,
        age: 34,
        heightCm: 181.0,
        trendKg: 78.0,
        softMode: true,
      ));
    });

    test('Body off from the enabled modules gives bodyOn false', () async {
      final setup = await setupGoals(modules: {ModuleId.goals});

      final facts = await setup.container.read(intakeFactsProvider.future);

      expect(facts.bodyOn, isFalse);
    });

    test('no weigh-in gives a null trend', () async {
      final setup = await setupGoals(
        weightOverride: weightSummaryProvider.overrideWith((ref) async => null),
      );

      final facts = await setup.container.read(intakeFactsProvider.future);

      expect(facts.trendKg, isNull);
    });

    test('no profile gives a null age and a null height', () async {
      final setup = await setupGoals(profileOverride: _profile(null));

      final facts = await setup.container.read(intakeFactsProvider.future);

      expect(facts.age, isNull);
      expect(facts.heightCm, isNull);
    });

    test('no screening gives a null soft mode', () async {
      final setup = await setupGoals();

      final facts = await setup.container.read(intakeFactsProvider.future);

      expect(facts.softMode, isNull);
    });

    test('born in December 2008 reads 18 in 2026 and is not under18', () async {
      final setup = await setupGoals(
        profileOverride: _profile(const UserProfile(birthYear: 2008)),
      );

      final facts = await setup.container.read(intakeFactsProvider.future);

      expect(facts.age, 18);
      expect(weightGoalBlock(facts), isNot(IntakeBlock.under18));
    });

    test('born in 2009 reads 17 and gives under18', () async {
      final setup = await setupGoals(
        profileOverride: _profile(const UserProfile(birthYear: 2009)),
      );

      final facts = await setup.container.read(intakeFactsProvider.future);

      expect(facts.age, 17);
      expect(weightGoalBlock(facts), IntakeBlock.under18);
    });

    test('a submit changes the soft mode of the facts', () async {
      final setup = await setupGoals();
      final before = await setup.container.read(intakeFactsProvider.future);

      await setup.container.read(screeningControllerProvider).submit(_answers);

      final after = await setup.container.read(intakeFactsProvider.future);
      expect(before.softMode, isNull);
      expect(after.softMode, isTrue);
    });
  });
}
