import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/application/step_goal_history_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/goals/application/goal_ender.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_end.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

import '../goal_fixtures.dart';

final LocalDate _today = goalDay(12, 7);
final LocalDate _yesterday = goalDay(12, 6);
final LocalDate _planRaiseDay = goalDay(11, 23);
final LocalDate _acceptedMonday = goalDay(11, 30);

const _stepsTo10000 = LeverChange(kind: LeverKind.steps, from: 9000, to: 10000);

final class _Profiles implements UserProfileStore {
  new(this.profile);

  UserProfile? profile;
  bool failing = false;
  int saves = 0;

  @override
  Future<UserProfile?> read() async => profile;

  @override
  Future<void> save(UserProfile profile, {required DateTime at}) async {
    if (failing) throw StateError('the profile was not saved');
    saves++;
    this.profile = profile;
  }
}

final class _Rig {
  new(this.setup, this.profiles, this.history);

  final GoalSetup setup;
  final _Profiles profiles;
  final InMemoryStepGoalHistory history;

  GoalEnder get ender => setup.container.read(goalEnderProvider.notifier);
  InMemoryGoalStore get store => setup.store;
  int get revision => setup.revision;
  int get stepGoal => setup.container.read(stepGoalProvider);

  Future<Goal> goal() async => (await store.goals()).first;

  Future<List<StepGoalChange>> changes() => history.changes();

  Future<int> goalOn(LocalDate date) async => stepGoalOn(
    date,
    changes: await changes(),
    current: profiles.profile?.dailyStepGoal ?? defaultStepGoal,
  );
}

// raised: the plan took the goal from 8000 to 10000 on an accepted week, as
// the reviewer writes it, and the person has not touched it since.
Future<_Rig> _rig({
  Set<ModuleId> modules = goalModules,
  bool demo = false,
  bool raised = true,
  bool withGoal = true,
  _Profiles? profiles,
}) async {
  final held =
      profiles ?? _Profiles(UserProfile(dailyStepGoal: raised ? 10000 : 8000));
  final history = InMemoryStepGoalHistory();
  final setup = await setupGoals(
    modules: modules,
    draft: withGoal ? goalDraft() : null,
    profileOverride: userProfileStoreProvider.overrideWithValue(held),
    extraOverrides: [
      stepGoalHistoryProvider.overrideWithValue(history),
      demoModeStoreProvider.overrideWithValue(
        InMemoryDemoModeStore(enabled: demo),
      ),
    ],
  );
  setup.container.listen(userProfileProvider, (_, _) {});
  setup.container.listen(demoModeProvider, (_, _) {});
  await setup.container.read(userProfileProvider.future);
  if (raised) {
    await history.record(on: _planRaiseDay, steps: 10000, previous: 8000);
    await _addWeek(setup.store, _acceptedMonday, answer: WeekAnswer.accepted);
  }
  return _Rig(setup, held, history);
}

Future<void> _addWeek(
  InMemoryGoalStore store,
  LocalDate monday, {
  LeverChange change = _stepsTo10000,
  WeekAnswer? answer,
}) async {
  await store.addWeek(
    1,
    monday: monday,
    inputs: f1,
    review: Review(
      rule: ReviewRule.build,
      action: ReviewAction.nextStep,
      adherence: 1,
      change: change,
    ),
  );
  if (answer == null) return;
  await store.answer(1, monday, answer);
}

void main() {
  group('criterion 1: end and keep the step goal', () {
    test('returns ended and ends the goal with reason person today', () async {
      final rig = await _rig();

      final outcome = await rig.ender.end(GoalEndReason.person);

      expect(outcome, GoalEndOutcome.ended);
      final goal = await rig.goal();
      expect(goal.phase, GoalPhase.ended);
      expect(goal.endReason, GoalEndReason.person);
      expect(goal.endedOn, _today);
      expect(await rig.store.active(), isNull);
    });

    test('leaves the profile and the rows as they were', () async {
      final rig = await _rig();
      final rows = await rig.changes();

      await rig.ender.end(GoalEndReason.person);

      expect(await rig.changes(), rows);
      expect(rig.profiles.saves, 0);
      expect(rig.profiles.profile?.dailyStepGoal, 10000);
      expect(rig.stepGoal, 10000);
    });

    test('bumps the data revision', () async {
      final rig = await _rig();
      final before = rig.revision;

      await rig.ender.end(GoalEndReason.person);

      expect(rig.revision, greaterThan(before));
    });

    test('a goal the plan never raised ends the same way', () async {
      final rig = await _rig(raised: false);

      final outcome = await rig.ender.end(GoalEndReason.person);

      expect(outcome, GoalEndOutcome.ended);
      expect(await rig.changes(), isEmpty);
      expect(rig.profiles.saves, 0);
    });

    test('a week waiting for an answer stays unanswered', () async {
      final rig = await _rig(raised: false);
      await _addWeek(rig.store, _acceptedMonday);

      await rig.ender.end(GoalEndReason.person);

      final week = (await rig.store.weeks(1)).single;
      expect(week.answer, isNull);
      expect(week.change, isNotNull);
    });
  });

  group('criterion 2: end and go back to X', () {
    test('the fixture raised 8000 to 10000', () async {
      final rig = await _rig();

      final raise = await rig.setup.container.read(goalEndRaiseProvider.future);

      expect(raise, (from: 8000, to: 10000));
    });

    test('ends the goal and writes X to the profile', () async {
      final rig = await _rig();

      final outcome = await rig.ender.end(
        GoalEndReason.person,
        stepGoalBack: 8000,
      );

      expect(outcome, GoalEndOutcome.ended);
      expect((await rig.goal()).endReason, GoalEndReason.person);
      expect(rig.profiles.profile?.dailyStepGoal, 8000);
      expect(rig.stepGoal, 8000);
    });

    test('writes one new change row dated today with X', () async {
      final rig = await _rig();
      final before = await rig.changes();

      await rig.ender.end(GoalEndReason.person, stepGoalBack: 8000);

      expect(await rig.changes(), [...before, (from: _today, steps: 8000)]);
    });

    test('the Day Score step goal of yesterday does not change', () async {
      final rig = await _rig();
      final before = await rig.goalOn(_yesterday);

      await rig.ender.end(GoalEndReason.person, stepGoalBack: 8000);

      expect(before, 10000);
      expect(await rig.goalOn(_yesterday), before);
      expect(await rig.goalOn(_today), 8000);
    });

    test('keeps the rest of the profile', () async {
      final rig = await _rig(
        profiles: _Profiles(
          const UserProfile(heightCentimeters: 178, dailyStepGoal: 10000),
        ),
      );

      await rig.ender.end(GoalEndReason.person, stepGoalBack: 8000);

      expect(rig.profiles.profile?.heightCentimeters, 178);
    });

    test('works for a switch too', () async {
      final rig = await _rig();

      final outcome = await rig.ender.end(
        GoalEndReason.switched,
        stepGoalBack: 8000,
      );

      expect(outcome, GoalEndOutcome.ended);
      expect((await rig.goal()).endReason, GoalEndReason.switched);
      expect(rig.profiles.profile?.dailyStepGoal, 8000);
    });

    test('a week waiting for an answer stays unanswered', () async {
      final rig = await _rig();
      await _addWeek(
        rig.store,
        goalDay(12, 7),
        change: const LeverChange(
          kind: LeverKind.steps,
          from: 10000,
          to: 11000,
        ),
      );

      await rig.ender.end(GoalEndReason.person, stepGoalBack: 8000);

      expect((await rig.store.weeks(1)).last.answer, isNull);
    });
  });

  group('criterion 3: switch', () {
    test('ends the goal with reason switched today', () async {
      final rig = await _rig(raised: false);

      final outcome = await rig.ender.end(GoalEndReason.switched);

      expect(outcome, GoalEndOutcome.ended);
      final goal = await rig.goal();
      expect(goal.endReason, GoalEndReason.switched);
      expect(goal.endedOn, _today);
      expect(await rig.store.active(), isNull);
    });

    test('a start the same day returns a goal', () async {
      final rig = await _rig(raised: false);
      await rig.ender.end(GoalEndReason.switched);

      final started = await rig.store.start(goalDraft(startedOn: _today));

      expect(started, isNotNull);
      expect(started?.id, 2);
      expect((await rig.store.active())?.id, 2);
    });

    test('switch then back without picking keeps the goal ended', () async {
      final rig = await _rig(raised: false);

      await rig.ender.end(GoalEndReason.switched);

      expect(await rig.store.active(), isNull);
      expect(await rig.store.goals(), hasLength(1));
    });
  });

  group('the reason is person or switched', () {
    for (final reason in [GoalEndReason.protection, GoalEndReason.unreadable]) {
      test('${reason.name} throws ArgumentError and writes nothing', () async {
        final rig = await _rig();
        final revision = rig.revision;

        await expectLater(
          () async => rig.ender.end(reason),
          throwsArgumentError,
        );

        expect((await rig.store.active())?.id, 1);
        expect(rig.revision, revision);
        expect(rig.profiles.saves, 0);
      });
    }
  });

  group('criterion 5: a profile write that fails', () {
    Future<_Rig> failing() async {
      final rig = await _rig();
      rig.profiles.failing = true;
      return rig;
    }

    test('returns stepGoalFailed and the goal stays ended', () async {
      final rig = await failing();

      final outcome = await rig.ender.end(
        GoalEndReason.person,
        stepGoalBack: 8000,
      );

      expect(outcome, GoalEndOutcome.stepGoalFailed);
      final goal = await rig.goal();
      expect(goal.phase, GoalPhase.ended);
      expect(goal.endReason, GoalEndReason.person);
      expect(rig.profiles.profile?.dailyStepGoal, 10000);
    });

    test('does not throw out of end', () async {
      final rig = await failing();

      await expectLater(
        rig.ender.end(GoalEndReason.switched, stepGoalBack: 8000),
        completes,
      );
    });

    test('a second end is refused', () async {
      final rig = await failing();
      await rig.ender.end(GoalEndReason.person, stepGoalBack: 8000);

      final second = await rig.ender.end(
        GoalEndReason.person,
        stepGoalBack: 8000,
      );

      expect(second, GoalEndOutcome.refused);
    });

    test('retry with a working store writes the profile', () async {
      final rig = await failing();
      await rig.ender.end(GoalEndReason.person, stepGoalBack: 8000);
      rig.profiles.failing = false;

      final done = await rig.ender.retryStepGoalBack(8000);

      expect(done, isTrue);
      expect(rig.profiles.profile?.dailyStepGoal, 8000);
      expect(rig.stepGoal, 8000);
    });

    test('retry writes no second change row', () async {
      final rig = await failing();
      await rig.ender.end(GoalEndReason.person, stepGoalBack: 8000);
      rig.profiles.failing = false;

      await rig.ender.retryStepGoalBack(8000);

      final rows = await rig.changes();
      expect(rows.where((row) => row.steps == 8000), hasLength(2));
      expect(rows.where((row) => row.from == _today), hasLength(1));
      expect(rows.last, (from: _today, steps: 8000));
    });

    test('retry with a store that still fails returns false', () async {
      final rig = await failing();
      await rig.ender.end(GoalEndReason.person, stepGoalBack: 8000);

      final done = await rig.ender.retryStepGoalBack(8000);

      expect(done, isFalse);
      expect(rig.profiles.profile?.dailyStepGoal, 10000);
    });

    test('retry is not gated on an active goal', () async {
      final rig = await failing();
      await rig.ender.end(GoalEndReason.person, stepGoalBack: 8000);
      rig.profiles.failing = false;
      expect(await rig.store.active(), isNull);

      final done = await rig.ender.retryStepGoalBack(8000);

      expect(done, isTrue);
    });

    test('retry only lowers: a goal set lower by hand stays', () async {
      final rig = await failing();
      await rig.ender.end(GoalEndReason.person, stepGoalBack: 8000);
      rig.profiles.failing = false;
      rig.profiles.profile = const UserProfile(dailyStepGoal: 7000);
      rig.setup.container.invalidate(userProfileProvider);
      await rig.setup.container.read(userProfileProvider.future);

      await rig.ender.retryStepGoalBack(8000);

      expect(rig.profiles.profile?.dailyStepGoal, 7000);
      expect(rig.profiles.saves, 0);
    });

    test('retry never raises the goal', () async {
      final rig = await _rig(raised: false);

      await rig.ender.retryStepGoalBack(12000);

      expect(rig.profiles.profile?.dailyStepGoal, 8000);
      expect(rig.profiles.saves, 0);
      expect(await rig.changes(), isEmpty);
    });
  });

  group('criterion 6: refused and nothing written', () {
    Future<void> expectUntouched(_Rig rig, {int? stepGoalBack}) async {
      final rows = await rig.changes();

      final outcome = await rig.ender.end(
        GoalEndReason.person,
        stepGoalBack: stepGoalBack,
      );

      expect(outcome, GoalEndOutcome.refused);
      expect((await rig.store.active())?.id, 1);
      expect((await rig.goal()).endReason, isNull);
      expect(await rig.changes(), rows);
      expect(rig.profiles.profile?.dailyStepGoal, 10000);
      expect(rig.profiles.saves, 0);
      expect(rig.revision, 0);
    }

    test('demo mode', () async {
      await expectUntouched(await _rig(demo: true));
    });

    test('demo mode with a step goal to go back to', () async {
      await expectUntouched(await _rig(demo: true), stepGoalBack: 8000);
    });

    test('demo mode refuses a switch too', () async {
      final rig = await _rig(demo: true);

      final outcome = await rig.ender.end(GoalEndReason.switched);

      expect(outcome, GoalEndOutcome.refused);
      expect((await rig.store.active())?.id, 1);
      expect(rig.revision, 0);
    });

    test('Goals off', () async {
      await expectUntouched(await _rig(modules: const {}));
    });

    test('Goals off with a step goal to go back to', () async {
      await expectUntouched(await _rig(modules: const {}), stepGoalBack: 8000);
    });

    test('no active goal', () async {
      final rig = await _rig(raised: false, withGoal: false);

      final outcome = await rig.ender.end(
        GoalEndReason.person,
        stepGoalBack: 8000,
      );

      expect(outcome, GoalEndOutcome.refused);
      expect(await rig.store.goals(), isEmpty);
      expect(rig.profiles.saves, 0);
      expect(await rig.changes(), isEmpty);
      expect(rig.revision, 0);
    });

    test('a second tap is refused and writes nothing new', () async {
      final rig = await _rig();
      await rig.ender.end(GoalEndReason.person, stepGoalBack: 8000);
      final revision = rig.revision;
      final rows = await rig.changes();

      final second = await rig.ender.end(
        GoalEndReason.person,
        stepGoalBack: 8000,
      );

      expect(second, GoalEndOutcome.refused);
      expect(rig.revision, revision);
      expect(await rig.changes(), rows);
      expect(rig.profiles.saves, 1);
    });

    test('a double tap ends once and writes one row', () async {
      final rig = await _rig();
      final before = await rig.changes();

      final outcomes = await Future.wait([
        rig.ender.end(GoalEndReason.person, stepGoalBack: 8000),
        rig.ender.end(GoalEndReason.person, stepGoalBack: 8000),
      ]);

      expect(outcomes.where((o) => o == GoalEndOutcome.ended), hasLength(1));
      expect(outcomes.where((o) => o == GoalEndOutcome.refused), hasLength(1));
      expect(await rig.changes(), [...before, (from: _today, steps: 8000)]);
      expect(rig.profiles.saves, 1);
    });
  });

  group('criterion 7: lose fat with Body off', () {
    test('can be ended', () async {
      final rig = await _rig(modules: const {ModuleId.goals});

      final outcome = await rig.ender.end(GoalEndReason.person);

      expect(outcome, GoalEndOutcome.ended);
      expect((await rig.goal()).endReason, GoalEndReason.person);
      expect(await rig.store.active(), isNull);
    });

    test('can be switched', () async {
      final rig = await _rig(modules: const {ModuleId.goals});

      final outcome = await rig.ender.end(GoalEndReason.switched);

      expect(outcome, GoalEndOutcome.ended);
      expect((await rig.goal()).endReason, GoalEndReason.switched);
    });

    test('can be ended going back to X', () async {
      final rig = await _rig(modules: const {ModuleId.goals});

      final outcome = await rig.ender.end(
        GoalEndReason.person,
        stepGoalBack: 8000,
      );

      expect(outcome, GoalEndOutcome.ended);
      expect(rig.profiles.profile?.dailyStepGoal, 8000);
    });
  });

  group('the raise the end screen reads', () {
    test('is null for a goal the plan never raised', () async {
      final rig = await _rig(raised: false);

      final raise = await rig.setup.container.read(goalEndRaiseProvider.future);

      expect(raise, isNull);
    });

    test('is null when a raise was by hand only', () async {
      final rig = await _rig(raised: false);
      await rig.history.record(on: _planRaiseDay, steps: 10000, previous: 8000);
      rig.profiles.profile = const UserProfile(dailyStepGoal: 10000);
      rig.setup.container.invalidate(userProfileProvider);
      await rig.setup.container.read(userProfileProvider.future);

      final raise = await rig.setup.container.read(goalEndRaiseProvider.future);

      expect(raise, isNull);
    });
  });
}
