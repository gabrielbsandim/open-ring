import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/application/step_goal_history_providers.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/goals/application/goal_reviewer.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

import '../goal_fixtures.dart';

final LocalDate _monday = goalDay(12, 7);

final ReviewInputs _open = f1With(
  energy: null,
  energyPrevious: CheckInEnergy.normal,
  foodOrWeight: null,
);

final class _Profiles implements UserProfileStore {
  new(this.profile);

  UserProfile? profile;
  bool readFails = false;

  @override
  Future<UserProfile?> read() async {
    if (readFails) throw StateError('the profile was not read');
    return profile;
  }

  @override
  Future<void> save(UserProfile profile, {required DateTime at}) async =>
      this.profile = profile;
}

typedef _Rig = ({
  GoalSetup setup,
  _Profiles profiles,
  InMemoryStepGoalHistory history,
});

Future<_Rig> _rig({
  int? profileGoal = 8000,
  bool demo = false,
  Set<ModuleId> modules = goalModules,
  bool readFails = false,
}) async {
  final profiles = _Profiles(UserProfile(dailyStepGoal: profileGoal))
    ..readFails = readFails;
  final history = InMemoryStepGoalHistory();
  final setup = await setupGoals(
    modules: modules,
    draft: goalDraft(),
    profileOverride: userProfileStoreProvider.overrideWithValue(profiles),
    extraOverrides: [
      stepGoalHistoryProvider.overrideWithValue(history),
      demoModeStoreProvider.overrideWithValue(
        InMemoryDemoModeStore(enabled: demo),
      ),
    ],
  );
  setup.container.listen(userProfileProvider, (_, _) {});
  setup.container.listen(demoModeProvider, (_, _) {});
  await setup.container.read(userProfileProvider.future).catchError((_) {
    return null;
  });
  return (setup: setup, profiles: profiles, history: history);
}

Future<void> _addWeek(_Rig rig, LeverChange? change) => rig.setup.store.addWeek(
  1,
  monday: _monday,
  inputs: _open,
  review: Review(
    rule: change == null ? ReviewRule.holdOther : ReviewRule.build,
    action: change == null ? ReviewAction.hold : ReviewAction.nextStep,
    adherence: 1,
    change: change,
  ),
);

GoalReviewer _reviewer(_Rig rig) =>
    rig.setup.container.read(goalReviewerProvider.notifier);

void main() {
  group('checkIn refuses where an answer is refused', () {
    test('and amends otherwise', () async {
      final rig = await _rig();
      await _addWeek(rig, null);
      final review = await _reviewer(rig)
          .checkIn(_monday, energy: CheckInEnergy.low);
      expect(review, isNotNull);
      expect(
        (await rig.setup.store.weeks(1)).last.inputs.energy,
        CheckInEnergy.low,
      );
    });

    test('in demo mode', () async {
      final rig = await _rig(demo: true);
      await _addWeek(rig, null);
      final review = await _reviewer(rig)
          .checkIn(_monday, energy: CheckInEnergy.low);
      expect(review, isNull);
      expect((await rig.setup.store.weeks(1)).last.inputs.energy, isNull);
    });

    test('for a weight goal with Body off', () async {
      final rig = await _rig(modules: goalModules.difference({ModuleId.body}));
      await _addWeek(rig, null);
      final review = await _reviewer(rig)
          .checkIn(_monday, energy: CheckInEnergy.low);
      expect(review, isNull);
      expect((await rig.setup.store.weeks(1)).last.inputs.energy, isNull);
    });
  });

  test('a profile with no step goal counts as 8,000', () async {
    final rig = await _rig(profileGoal: null);
    await _addWeek(
      rig,
      const LeverChange(kind: LeverKind.steps, from: 7500, to: 8000),
    );
    final outcome = await _reviewer(rig).answer(_monday, WeekAnswer.accepted);
    expect(outcome, ReviewAnswerOutcome.accepted);
    expect(await rig.history.changes(), isEmpty);
    expect(rig.profiles.profile?.dailyStepGoal, isNull);
  });

  test(
    'a profile that cannot be read keeps the answer and fails the goal',
    () async {
      final rig = await _rig(readFails: true);
      await _addWeek(
        rig,
        const LeverChange(kind: LeverKind.steps, from: 9000, to: 10000),
      );
      final outcome = await _reviewer(rig).answer(_monday, WeekAnswer.accepted);
      expect(outcome, ReviewAnswerOutcome.stepGoalFailed);
      expect((await rig.setup.store.weeks(1)).last.answer, WeekAnswer.accepted);
      expect(await rig.history.changes(), isEmpty);
    },
  );

  test('a retry never lowers a goal set by hand meanwhile', () async {
    final rig = await _rig(profileGoal: 12000);
    final done = await _reviewer(rig).retryStepGoal(10000);
    expect(done, isTrue);
    expect(rig.profiles.profile?.dailyStepGoal, 12000);
    expect(await rig.history.changes(), isEmpty);
  });
}
