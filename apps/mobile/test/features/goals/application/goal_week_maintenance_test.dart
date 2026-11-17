import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/step_goal_history_providers.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_reviewer.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';

import '../goal_fixtures.dart';

final LocalDate _monday = goalDay(12, 7);
final LocalDate _until = _monday.addDays(27);

const _stepsChange = LeverChange(kind: LeverKind.steps, from: 9000, to: 10000);

Future<GoalSetup> _setup({
  Set<ModuleId> modules = goalModules,
  GoalDraft? draft,
}) async {
  final setup = await setupGoals(
    modules: modules,
    draft: draft ?? goalDraft(),
    extraOverrides: <Override>[
      stepGoalHistoryProvider.overrideWithValue(InMemoryStepGoalHistory()),
      demoModeStoreProvider.overrideWithValue(InMemoryDemoModeStore()),
    ],
  );
  setup.container
    ..listen(goalWeekProvider, (_, _) {})
    ..listen(demoModeProvider, (_, _) {})
    ..listen(userProfileProvider, (_, _) {});
  await setup.container.read(userProfileProvider.future);
  return setup;
}

Future<void> _maintain(GoalSetup setup, {LocalDate? until, bool set = true}) {
  final end = set ? (until ?? _until) : null;
  return setup.store.setPhase(
    1,
    GoalPhase.maintenance,
    since: _monday,
    until: end,
  );
}

void _bump(GoalSetup setup) =>
    setup.container.read(dataRevisionProvider.notifier).bump();

Future<GoalWeekView> _view(GoalSetup setup) {
  _bump(setup);
  return setup.container.read(goalWeekProvider.future);
}

Future<void> _addProposal(GoalSetup setup, ReviewInputs inputs) async {
  final written = await setup.store.addWeek(
    1,
    monday: _monday,
    inputs: inputs,
    review: Review(
      rule: ReviewRule.build,
      action: ReviewAction.nextStep,
      adherence: 1,
      change: _stepsChange,
    ),
  );
  expect(written, isTrue);
}

void main() {
  group('G11b2 interface: GoalMaintenance', () {
    test('equal when until and over are equal', () {
      final a = GoalMaintenance(until: _until, over: false);
      final b = GoalMaintenance(until: _until, over: false);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs by over', () {
      expect(
        GoalMaintenance(until: _until, over: false),
        isNot(GoalMaintenance(until: _until, over: true)),
      );
    });

    test('differs by until', () {
      expect(
        GoalMaintenance(until: _until, over: false),
        isNot(GoalMaintenance(until: _until.addDays(1), over: false)),
      );
    });
  });

  group('G11b2 criterion 4: the week view in maintenance', () {
    test('a block carries no maintenance', () async {
      final setup = await _setup();

      final view = await _view(setup);

      expect(view, isA<GoalWeekRunning>());
      expect((view as GoalWeekRunning).maintenance, isNull);
    });

    test('carries until and over false while it lasts', () async {
      final setup = await _setup();
      await _maintain(setup);

      final view = await _view(setup) as GoalWeekRunning;

      expect(view.maintenance, GoalMaintenance(until: _until, over: false));
    });

    test('the last day is not over', () async {
      final setup = await _setup();
      await _maintain(setup, until: _monday);

      final view = await _view(setup) as GoalWeekRunning;

      expect(view.maintenance, GoalMaintenance(until: _monday, over: false));
    });

    test('the day after until is over', () async {
      final setup = await _setup();
      await _maintain(setup, until: _monday.addDays(-1));

      final view = await _view(setup) as GoalWeekRunning;

      expect(
        view.maintenance,
        GoalMaintenance(until: _monday.addDays(-1), over: true),
      );
    });

    test('a null phaseUntil carries no maintenance', () async {
      final setup = await _setup();
      await _maintain(setup, set: false);

      final view = await _view(setup) as GoalWeekRunning;

      expect(view.maintenance, isNull);
      expect(view.levers, hasLength(3));
    });

    test('review is null even when this Monday row is pending', () async {
      final setup = await _setup();
      await _addProposal(setup, f1);
      await _maintain(setup);

      final view = await _view(setup) as GoalWeekRunning;

      expect(view.review, isNull);
      expect(view.maintenance, isNotNull);
    });

    test('a block with a pending row still shows its review', () async {
      final setup = await _setup();
      await _addProposal(setup, f1);

      final view = await _view(setup) as GoalWeekRunning;

      expect(view.review, isNotNull);
      expect(view.maintenance, isNull);
    });

    test('a recovery row carries maintenance too', () async {
      final setup = await _setup();
      final inputs = f1Recovering(recoveryPrevious: false);
      await setup.store.addWeek(
        1,
        monday: _monday,
        inputs: inputs,
        review: reviewWeek(inputs),
      );
      await _maintain(setup);

      final view = await _view(setup);

      expect(view, isA<GoalWeekRecovery>());
      expect(
        (view as GoalWeekRecovery).maintenance,
        GoalMaintenance(until: _until, over: false),
      );
    });

    test('Body off in maintenance is the hold, with no maintenance', () async {
      final setup = await _setup(modules: {ModuleId.goals});
      await _maintain(setup);

      expect(await _view(setup), isA<GoalWeekHold>());
    });
  });

  group('G11b2 interface: canMaintainNow', () {
    final loseFat = Goal.started(1, goalDraft());

    GoalWeekView running(Goal goal, {GoalMaintenance? maintenance}) =>
        GoalWeekRunning(
          goal: goal,
          monday: _monday,
          week: 4,
          levers: const [],
          review: null,
          maintenance: maintenance,
        );

    test('a running block of a lose fat goal', () {
      expect(canMaintainNow(running(loseFat)), isTrue);
    });

    test('a recovery week of a block', () {
      expect(
        canMaintainNow(
          GoalWeekRecovery(goal: loseFat, monday: _monday, week: 4),
        ),
        isTrue,
      );
    });

    test('a running view in maintenance', () {
      final view = running(
        loseFat,
        maintenance: GoalMaintenance(until: _until, over: false),
      );

      expect(canMaintainNow(view), isFalse);
    });

    test('a recovery view in maintenance', () {
      final view = GoalWeekRecovery(
        goal: loseFat,
        monday: _monday,
        week: 4,
        maintenance: GoalMaintenance(until: _until, over: false),
      );

      expect(canMaintainNow(view), isFalse);
    });

    for (final kind in [GoalKind.getFitter, GoalKind.sleepBetter]) {
      test('a ${kind.name} goal', () {
        final goal = Goal.started(1, goalDraft(kind: kind));

        expect(canMaintainNow(running(goal)), isFalse);
      });
    }

    test('every other state', () {
      final views = <GoalWeekView>[
        const GoalWeekOff(),
        const GoalWeekNoGoal(),
        GoalWeekHold(goal: loseFat),
        GoalWeekBase(goal: loseFat, rate: null),
        GoalWeekPaused(goal: loseFat, until: _until, rule: null, over: false),
      ];

      expect(views.map(canMaintainNow), everyElement(isFalse));
    });
  });

  group('G11b2 criterion 5: answer in maintenance is refused', () {
    Future<GoalSetup> pending() async {
      final setup = await _setup();
      await _addProposal(
        setup,
        f1With(
          energy: null,
          energyPrevious: CheckInEnergy.normal,
          foodOrWeight: null,
        ),
      );
      await _maintain(setup);
      return setup;
    }

    for (final choice in WeekAnswer.values) {
      test('${choice.name} is refused before anything is written', () async {
        final setup = await pending();
        final revision = setup.revision;

        final outcome = await setup.reviewer.answer(_monday, choice);

        expect(outcome, ReviewAnswerOutcome.refused);
        final row = (await setup.weeks()).single;
        expect(row.answer, isNull);
        expect(row.change, isNotNull);
        expect(setup.revision, revision);
        expectSameLevers((await setup.store.active())!.levers, const [
          strengthLever,
          sleepLever,
          stepsLever,
        ]);
      });
    }

    test('a check-in sent with the answer is not amended', () async {
      final setup = await pending();
      final revision = setup.revision;

      final outcome = await setup.reviewer.answer(
        _monday,
        WeekAnswer.accepted,
        energy: CheckInEnergy.good,
        foodOrWeight: false,
      );

      expect(outcome, ReviewAnswerOutcome.refused);
      final row = (await setup.weeks()).single;
      expect(row.inputs.energy, isNull);
      expect(row.inputs.foodOrWeight, isNull);
      expect(setup.revision, revision);
    });

    test('checkIn still amends a maintenance row', () async {
      final setup = await _setup();
      await _maintain(setup);
      await setup.reviewer.reviewDueWeek();

      final review = await setup.reviewer.checkIn(
        _monday,
        energy: CheckInEnergy.good,
      );

      expect(review, isNotNull);
      expect((await setup.weeks()).single.inputs.energy, CheckInEnergy.good);
    });

    test('retryStepGoal is not refused in maintenance', () async {
      final setup = await _setup();
      await _maintain(setup);

      expect(await setup.reviewer.retryStepGoal(10000), isTrue);
    });
  });
}
