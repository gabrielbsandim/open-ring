import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/application/step_goal_history_providers.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/goals/application/goal_reviewer.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

import '../goal_fixtures.dart';

final _monday = goalDay(12, 7);

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
  new(this.setup, this.profiles, this.history, this.demo);

  final GoalSetup setup;
  final _Profiles profiles;
  final InMemoryStepGoalHistory history;
  final InMemoryDemoModeStore demo;

  GoalReviewer get reviewer => setup.reviewer;
  InMemoryGoalStore get store => setup.store;
  int get revision => setup.revision;

  Future<GoalWeek> week() async => (await store.weeks(1)).last;

  Future<List<Lever>> levers() async => (await store.active())!.levers;

  Future<int?> stepsLever() async => (await levers())
      .where((lever) => lever.kind == LeverKind.steps)
      .map((lever) => lever.target)
      .firstOrNull;

  int get stepGoal => setup.container.read(stepGoalProvider);

  Future<List<StepGoalChange>> changes() => history.changes();
}

Future<_Rig> _rig({
  Set<ModuleId> modules = goalModules,
  InMemoryGoalStore? store,
  _Profiles? profiles,
  InMemoryStepGoalHistory? history,
  bool demo = false,
  int? profileGoal = 8000,
  GoalDraft? draft,
}) async {
  final held = profiles ?? _Profiles(UserProfile(dailyStepGoal: profileGoal));
  final steps = history ?? InMemoryStepGoalHistory();
  final mode = InMemoryDemoModeStore(enabled: demo);
  final setup = await setupGoals(
    modules: modules,
    store: store,
    draft: store == null ? (draft ?? goalDraft()) : null,
    profileOverride: userProfileStoreProvider.overrideWithValue(held),
    extraOverrides: [
      stepGoalHistoryProvider.overrideWithValue(steps),
      demoModeStoreProvider.overrideWithValue(mode),
    ],
  );
  setup.container.listen(userProfileProvider, (_, _) {});
  await setup.container.read(userProfileProvider.future);
  return _Rig(setup, held, steps, mode);
}

Future<_Rig> _reviewed({
  int? profileGoal = 8000,
  _Profiles? profiles,
  GoalDraft? draft,
}) async {
  final rig = await _rig(
    profileGoal: profileGoal,
    profiles: profiles,
    draft: draft,
  );
  await rig.reviewer.reviewDueWeek();
  return rig;
}

Future<_Rig> _withChange(LeverChange change) async {
  final rig = await _rig();
  await rig.store.addWeek(
    1,
    monday: _monday,
    inputs: f1,
    review: Review(
      rule: ReviewRule.build,
      action: ReviewAction.nextStep,
      adherence: 1,
      change: change,
    ),
  );
  return rig;
}

Future<_Rig> _pausable() async {
  final rig = await _rig();
  final previous = f1With(
    energy: CheckInEnergy.low,
    energyPrevious: CheckInEnergy.normal,
    foodOrWeight: null,
  );
  final current = f1With(
    energy: null,
    energyPrevious: CheckInEnergy.low,
    foodOrWeight: null,
  );
  await rig.store.addWeek(
    1,
    monday: goalDay(11, 30),
    inputs: previous,
    review: reviewWeek(previous),
  );
  await rig.store.addWeek(
    1,
    monday: _monday,
    inputs: current,
    review: reviewWeek(current),
  );
  return rig;
}

const _stepsChange = LeverChange(kind: LeverKind.steps, from: 9000, to: 10000);
const _strengthChange = LeverChange(
  kind: LeverKind.strengthDays,
  from: 2,
  to: 3,
);
const _effortChange = LeverChange(
  kind: LeverKind.effortPoints,
  from: 100,
  to: 120,
);

final _baselineOf8000 = (from: stepGoalBaselineDate, steps: 8000);

void main() {
  group('criterion 1: accept a steps change above the profile goal', () {
    test('the fixture review proposes steps 9000 to 10000', () async {
      final rig = await _reviewed();

      final week = await rig.week();

      expect(week.change?.kind, LeverKind.steps);
      expect(week.change?.from, 9000);
      expect(week.change?.to, 10000);
      expect(week.answer, isNull);
    });

    test('returns accepted', () async {
      final rig = await _reviewed();

      final outcome = await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(outcome, ReviewAnswerOutcome.accepted);
    });

    test('answers the week accepted', () async {
      final rig = await _reviewed();

      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect((await rig.week()).answer, WeekAnswer.accepted);
    });

    test('puts the steps lever at 10000', () async {
      final rig = await _reviewed();

      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(await rig.stepsLever(), 10000);
    });

    test('writes one step goal change dated today with 10000', () async {
      final rig = await _reviewed();

      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(await rig.changes(), [
        _baselineOf8000,
        (from: _monday, steps: 10000),
      ]);
    });

    test('the profile and stepGoalProvider read 10000', () async {
      final rig = await _reviewed();

      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(rig.profiles.profile?.dailyStepGoal, 10000);
      expect(rig.stepGoal, 10000);
    });

    test('keeps the rest of the profile', () async {
      final rig = await _reviewed(
        profiles: _Profiles(
          const UserProfile(heightCentimeters: 178, dailyStepGoal: 8000),
        ),
      );

      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(rig.profiles.profile?.heightCentimeters, 178);
    });

    test('bumps the data revision', () async {
      final rig = await _reviewed();
      final before = rig.revision;

      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(rig.revision, greaterThan(before));
    });

    test('a profile with no step goal reads as 8000 and is raised', () async {
      final rig = await _reviewed(profileGoal: null);

      final outcome = await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(outcome, ReviewAnswerOutcome.accepted);
      expect(rig.profiles.profile?.dailyStepGoal, 10000);
      expect(await rig.changes(), [
        _baselineOf8000,
        (from: _monday, steps: 10000),
      ]);
    });

    test('no stored profile at all is raised to 10000', () async {
      final rig = await _reviewed(profiles: _Profiles(null));

      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(rig.profiles.profile?.dailyStepGoal, 10000);
      expect(rig.stepGoal, 10000);
    });
  });

  group('criterion 2: answers that write no step goal change', () {
    test('accept with a profile goal of 12000 answers and writes no '
        'row', () async {
      final rig = await _reviewed(profileGoal: 12000);

      final outcome = await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(outcome, ReviewAnswerOutcome.accepted);
      expect((await rig.week()).answer, WeekAnswer.accepted);
      expect(await rig.stepsLever(), 10000);
      expect(await rig.changes(), isEmpty);
      expect(rig.profiles.profile?.dailyStepGoal, 12000);
      expect(rig.profiles.saves, 0);
      expect(rig.stepGoal, 12000);
    });

    test('accept with a profile goal equal to the change writes no '
        'row', () async {
      final rig = await _reviewed(profileGoal: 10000);

      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(await rig.changes(), isEmpty);
      expect(rig.profiles.saves, 0);
    });

    test('keep returns kept, answers declined and writes no row', () async {
      final rig = await _reviewed();

      final outcome = await rig.reviewer.answer(_monday, WeekAnswer.declined);

      expect(outcome, ReviewAnswerOutcome.kept);
      expect((await rig.week()).answer, WeekAnswer.declined);
      expect(await rig.stepsLever(), 9000);
      expect(await rig.changes(), isEmpty);
      expect(rig.profiles.profile?.dailyStepGoal, 8000);
      expect(rig.stepGoal, 8000);
    });

    test('keep bumps the data revision', () async {
      final rig = await _reviewed();
      final before = rig.revision;

      await rig.reviewer.answer(_monday, WeekAnswer.declined);

      expect(rig.revision, greaterThan(before));
    });

    for (final change in [_strengthChange, _effortChange]) {
      test('accept of a ${change.kind.name} change answers and writes no '
          'row', () async {
        final rig = await _withChange(change);

        final outcome = await rig.reviewer.answer(_monday, WeekAnswer.accepted);

        expect(outcome, ReviewAnswerOutcome.accepted);
        expect((await rig.week()).answer, WeekAnswer.accepted);
        expect(await rig.changes(), isEmpty);
        expect(rig.profiles.profile?.dailyStepGoal, 8000);
        expect(rig.profiles.saves, 0);
      });
    }

    test('accept of a steps change that removes the lever writes no '
        'row', () async {
      final rig = await _withChange(
        const LeverChange(kind: LeverKind.steps, from: 9000, to: null),
      );

      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(await rig.changes(), isEmpty);
      expect(rig.profiles.saves, 0);
    });
  });

  group('criterion 3: a second or stale answer is refused', () {
    test('a second accept is refused and writes nothing new', () async {
      final rig = await _reviewed();
      await rig.reviewer.answer(_monday, WeekAnswer.accepted);
      final revision = rig.revision;
      final changes = await rig.changes();

      final second = await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(second, ReviewAnswerOutcome.refused);
      expect(rig.revision, revision);
      expect(await rig.changes(), changes);
      expect(rig.profiles.saves, 1);
      expect((await rig.week()).answer, WeekAnswer.accepted);
    });

    test('a keep after an accept is refused and the answer stays', () async {
      final rig = await _reviewed();
      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      final second = await rig.reviewer.answer(_monday, WeekAnswer.declined);

      expect(second, ReviewAnswerOutcome.refused);
      expect((await rig.week()).answer, WeekAnswer.accepted);
    });

    test('a double tap answers once and writes one row', () async {
      final rig = await _reviewed();

      final outcomes = await Future.wait([
        rig.reviewer.answer(_monday, WeekAnswer.accepted),
        rig.reviewer.answer(_monday, WeekAnswer.accepted),
      ]);

      expect(
        outcomes.where((o) => o == ReviewAnswerOutcome.accepted),
        hasLength(1),
      );
      expect(
        outcomes.where((o) => o == ReviewAnswerOutcome.refused),
        hasLength(1),
      );
      expect(await rig.changes(), [
        _baselineOf8000,
        (from: _monday, steps: 10000),
      ]);
      expect(rig.profiles.saves, 1);
    });

    test('a week that is no longer the newest is refused', () async {
      final rig = await _reviewed();
      final newer = f1With(
        energy: null,
        energyPrevious: null,
        foodOrWeight: null,
      );
      await rig.store.addWeek(
        1,
        monday: goalDay(12, 14),
        inputs: newer,
        review: reviewWeek(newer),
      );
      final revision = rig.revision;

      final outcome = await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(outcome, ReviewAnswerOutcome.refused);
      expect((await rig.store.weeks(1)).first.answer, isNull);
      expect(await rig.stepsLever(), 9000);
      expect(await rig.changes(), isEmpty);
      expect(rig.profiles.saves, 0);
      expect(rig.revision, revision);
    });

    test('a week that does not exist is refused', () async {
      final rig = await _reviewed();

      final outcome = await rig.reviewer.answer(
        goalDay(11, 30),
        WeekAnswer.accepted,
      );

      expect(outcome, ReviewAnswerOutcome.refused);
      expect(await rig.changes(), isEmpty);
    });

    test('a week with no change is refused', () async {
      final rig = await _rig();
      final inputs = f1With(
        energy: null,
        energyPrevious: null,
        foodOrWeight: null,
      );
      await rig.store.addWeek(
        1,
        monday: _monday,
        inputs: inputs,
        review: const Review(
          rule: ReviewRule.holdOnTrack,
          action: ReviewAction.hold,
          adherence: 1,
        ),
      );

      final outcome = await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(outcome, ReviewAnswerOutcome.refused);
      expect((await rig.week()).answer, isNull);
      expect(await rig.changes(), isEmpty);
    });
  });

  group('criterion 4: a profile write that fails', () {
    Future<_Rig> failing() async {
      final rig = await _reviewed(
        profiles: _Profiles(const UserProfile(dailyStepGoal: 8000)),
      );
      rig.profiles.failing = true;
      return rig;
    }

    test('returns stepGoalFailed and the week stays accepted', () async {
      final rig = await failing();

      final outcome = await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(outcome, ReviewAnswerOutcome.stepGoalFailed);
      expect((await rig.week()).answer, WeekAnswer.accepted);
      expect(await rig.stepsLever(), 10000);
      expect(rig.profiles.profile?.dailyStepGoal, 8000);
    });

    test('does not throw out of answer', () async {
      final rig = await failing();

      await expectLater(
        rig.reviewer.answer(_monday, WeekAnswer.accepted),
        completes,
      );
    });

    test('a second accept after the failure is refused', () async {
      final rig = await failing();
      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      final second = await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(second, ReviewAnswerOutcome.refused);
    });

    test('the answer write bumps the data revision', () async {
      final rig = await failing();
      final before = rig.revision;

      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(rig.revision, greaterThan(before));
    });

    test('retryStepGoal with a working store returns true and writes the '
        'profile', () async {
      final rig = await failing();
      await rig.reviewer.answer(_monday, WeekAnswer.accepted);
      rig.profiles.failing = false;

      final done = await rig.reviewer.retryStepGoal(10000);

      expect(done, isTrue);
      expect(rig.profiles.profile?.dailyStepGoal, 10000);
      expect(rig.stepGoal, 10000);
    });

    test('retryStepGoal adds no second history change', () async {
      final rig = await failing();
      await rig.reviewer.answer(_monday, WeekAnswer.accepted);
      rig.profiles.failing = false;

      await rig.reviewer.retryStepGoal(10000);

      final rows = await rig.changes();
      expect(rows.where((row) => row.steps == 10000), hasLength(1));
      expect(rows, [_baselineOf8000, (from: _monday, steps: 10000)]);
    });

    test('retryStepGoal with a store that still fails returns false', () async {
      final rig = await failing();
      await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      final done = await rig.reviewer.retryStepGoal(10000);

      expect(done, isFalse);
      expect(rig.profiles.profile?.dailyStepGoal, 8000);
    });

    test('retryStepGoal does not touch the week answer', () async {
      final rig = await failing();
      await rig.reviewer.answer(_monday, WeekAnswer.accepted);
      rig.profiles.failing = false;

      await rig.reviewer.retryStepGoal(10000);

      expect((await rig.week()).answer, WeekAnswer.accepted);
    });
  });

  group('criterion 5: a check-in that changes the rule', () {
    test('the fixture week proposes a change before the check-in', () async {
      final rig = await _pausable();

      final week = await rig.week();

      expect(week.change, isNotNull);
      expect(week.answer, isNull);
    });

    test('returns changed and writes no answer', () async {
      final rig = await _pausable();

      final outcome = await rig.reviewer.answer(
        _monday,
        WeekAnswer.accepted,
        energy: CheckInEnergy.low,
      );

      expect(outcome, ReviewAnswerOutcome.changed);
      final week = await rig.week();
      expect(week.answer, isNull);
      expect(week.rule, ReviewRule.pauseCheckIn);
      expect(week.inputs.energy, CheckInEnergy.low);
    });

    test('writes no step goal change and keeps the lever', () async {
      final rig = await _pausable();

      await rig.reviewer.answer(
        _monday,
        WeekAnswer.accepted,
        energy: CheckInEnergy.low,
      );

      expect(await rig.changes(), isEmpty);
      expect(rig.profiles.saves, 0);
      expect(await rig.stepsLever(), 9000);
      expect((await rig.store.active())!.phase, GoalPhase.paused);
    });

    test('a second consecutive food or weight yes changes the rule', () async {
      final rig = await _rig();
      final previous = f1With(
        energy: CheckInEnergy.normal,
        energyPrevious: CheckInEnergy.normal,
        foodOrWeight: true,
      );
      final current = ReviewInputs(
        kind: f1.kind,
        week: f1.week,
        levers: f1.levers,
        adherencePrevious: f1.adherencePrevious,
        baseline: f1.baseline,
        effortRaisesInRow: f1.effortRaisesInRow,
        rate: f1.rate,
        targetPercent: f1.targetPercent,
        capPercent: f1.capPercent,
        previousPercentLow: f1.previousPercentLow,
        bmi: f1.bmi,
        pregnantOrBreastfeeding: false,
        screeningPositive: false,
        bodyOn: f1.bodyOn,
        readiness: f1.readiness,
        recoveryPrevious: false,
        energy: null,
        energyPrevious: CheckInEnergy.normal,
        foodOrWeight: null,
        foodOrWeightPrevious: true,
      );
      await rig.store.addWeek(
        1,
        monday: goalDay(11, 30),
        inputs: previous,
        review: reviewWeek(previous),
      );
      await rig.store.addWeek(
        1,
        monday: _monday,
        inputs: current,
        review: reviewWeek(current),
      );
      expect((await rig.week()).change, isNotNull);

      final outcome = await rig.reviewer.answer(
        _monday,
        WeekAnswer.accepted,
        foodOrWeight: true,
      );

      expect(outcome, ReviewAnswerOutcome.changed);
      expect((await rig.week()).answer, isNull);
      expect(await rig.changes(), isEmpty);
    });

    test('bumps the data revision once for the check-in', () async {
      final rig = await _pausable();
      final before = rig.revision;

      await rig.reviewer.answer(
        _monday,
        WeekAnswer.accepted,
        energy: CheckInEnergy.low,
      );

      expect(rig.revision, before + 1);
    });

    test('a neutral check-in that keeps the rule still answers', () async {
      final rig = await _reviewed();

      final outcome = await rig.reviewer.answer(
        _monday,
        WeekAnswer.accepted,
        energy: CheckInEnergy.good,
        foodOrWeight: false,
      );

      expect(outcome, ReviewAnswerOutcome.accepted);
      expect((await rig.week()).answer, WeekAnswer.accepted);
      expect((await rig.week()).inputs.energy, CheckInEnergy.good);
    });
  });

  group('criterion 6: gates refuse and write nothing', () {
    Future<void> expectUntouched(_Rig rig) async {
      final outcome = await rig.reviewer.answer(_monday, WeekAnswer.accepted);

      expect(outcome, ReviewAnswerOutcome.refused);
      expect((await rig.week()).answer, isNull);
      expect(await rig.stepsLever(), 9000);
      expect(await rig.changes(), isEmpty);
      expect(rig.profiles.saves, 0);
      expect(rig.revision, 0);
    }

    test('demo mode', () async {
      final written = await _reviewed();
      final rig = await _rig(store: written.store, demo: true);

      await expectUntouched(rig);
    });

    test('demo mode refuses a keep too', () async {
      final written = await _reviewed();
      final rig = await _rig(store: written.store, demo: true);

      final outcome = await rig.reviewer.answer(_monday, WeekAnswer.declined);

      expect(outcome, ReviewAnswerOutcome.refused);
      expect((await rig.week()).answer, isNull);
      expect(rig.revision, 0);
    });

    test('Goals off', () async {
      final written = await _reviewed();
      final rig = await _rig(store: written.store, modules: const {});

      await expectUntouched(rig);
    });

    test('Body off under a lose fat goal', () async {
      final written = await _reviewed();
      final rig = await _rig(
        store: written.store,
        modules: const {ModuleId.goals},
      );

      await expectUntouched(rig);
    });

    test('Body off refuses a keep too', () async {
      final written = await _reviewed();
      final rig = await _rig(
        store: written.store,
        modules: const {ModuleId.goals},
      );

      final outcome = await rig.reviewer.answer(_monday, WeekAnswer.declined);

      expect(outcome, ReviewAnswerOutcome.refused);
      expect(rig.revision, 0);
    });
  });
}
