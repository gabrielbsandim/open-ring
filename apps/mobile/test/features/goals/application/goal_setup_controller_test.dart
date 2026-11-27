import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/domain/goal_setup.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

import '../goal_fixtures.dart';
import '../goal_picker_harness.dart';

GoalScreening _row(int day, {bool? softMode, bool? pregnant}) => GoalScreening(
  on: goalDay(12, day),
  softMode: softMode,
  pregnantOrBreastfeeding: pregnant,
);

// A seeded soft mode no is the setup step; 1992 makes the person 34.
Future<GoalSetup> _setup({
  Sex? sex = Sex.male,
  double? trendKg = 78.4,
  Set<ModuleId> modules = goalModules,
  bool demo = false,
  GoalDraft? draft,
  List<GoalScreening> rows = const [],
  bool seedNo = true,
  GoalStore Function(InMemoryGoalStore memory)? readStoreOf,
}) async {
  final setup = await setupPicker(
    modules: modules,
    profile: UserProfile(birthYear: 1992, heightCentimeters: 178, sex: sex),
    trendKg: trendKg,
    demo: demo,
    draft: draft,
    readStoreOf: readStoreOf,
  );
  if (seedNo) await setup.store.addScreening(_row(1, softMode: false));
  for (final row in rows) {
    await setup.store.addScreening(row);
  }
  return setup;
}

Future<SetupOutcome> _start(
  GoalSetup setup, {
  GoalPace pace = GoalPace.standard,
  double? referenceKg,
  bool? pregnant,
}) => setup.container
    .read(goalSetupControllerProvider)
    .start(
      pace: pace,
      referenceKg: referenceKg,
      pregnantOrBreastfeeding: pregnant,
    );

void main() {
  group('1. a male starts a goal without being asked', () {
    test(
      'starts with the trend as anchor, the reference and no levers',
      () async {
        final setup = await _setup();

        final outcome = await _start(setup, referenceKg: 74);

        final goal = await setup.store.active();
        expect(outcome, SetupOutcome.started);
        expect(goal, isNotNull);
        expect(goal!.kind, GoalKind.loseFat);
        expect(goal.pace, GoalPace.standard);
        expect(goal.startedOn, goalDay(12, 7));
        expect(goal.anchorKg, 78.4);
        expect(goal.referenceKg, 74.0);
        expect(goal.levers, isEmpty);
        expect(await setup.store.screenings(), hasLength(1));
      },
    );

    test('the gentle pace is stored and a null reference passes', () async {
      final setup = await _setup();

      final outcome = await _start(setup, pace: GoalPace.gentle);

      final goal = await setup.store.active();
      expect(outcome, SetupOutcome.started);
      expect(goal!.pace, GoalPace.gentle);
      expect(goal.referenceKg, isNull);
    });

    test('the answer is ignored when it was not asked', () async {
      final setup = await _setup();

      final outcome = await _start(setup, pregnant: true);

      expect(outcome, SetupOutcome.started);
      expect(await setup.store.screenings(), hasLength(1));
    });

    test('bumps the data revision once', () async {
      final setup = await _setup();

      await _start(setup);

      expect(setup.revision, 1);
    });
  });

  group('2. a female answering no', () {
    test('writes one pregnancy row with soft mode null and starts', () async {
      final setup = await _setup(sex: Sex.female);

      final outcome = await _start(setup, pregnant: false);

      final rows = await setup.store.screenings();
      expect(outcome, SetupOutcome.started);
      expect(rows, hasLength(2));
      expect(rows.first.softMode, isNull);
      expect(rows.first.pregnantOrBreastfeeding, isFalse);
      expect(rows.first.on, goalDay(12, 7));
      expect(await setup.store.active(), isNotNull);
      expect(setup.revision, 1);
    });

    test('a sex not given is asked as well', () async {
      final setup = await _setup(sex: null);

      final outcome = await _start(setup, pregnant: false);

      expect(outcome, SetupOutcome.started);
      expect(await setup.store.screenings(), hasLength(2));
    });

    test('the row is dated no earlier than the newest row', () async {
      final setup = await _setup(
        sex: Sex.female,
        rows: [_row(9, softMode: false)],
      );

      await _start(setup, pregnant: false);

      final rows = await setup.store.screenings();
      expect(rows.first.on, goalDay(12, 9));
      expect(rows.first.pregnantOrBreastfeeding, isFalse);
    });
  });

  group('3. an answer of yes', () {
    test('gives pregnancy, starts no goal and keeps the soft answer', () async {
      final setup = await _setup(sex: Sex.female);

      final outcome = await _start(setup, pregnant: true);

      final rows = await setup.store.screenings();
      expect(outcome, SetupOutcome.pregnancy);
      expect(await setup.store.goals(), isEmpty);
      expect(rows, hasLength(2));
      expect(rows.first.softMode, isNull);
      expect(rows.first.pregnantOrBreastfeeding, isTrue);
      expect(newestSoftMode(rows), isFalse);
      expect(setup.revision, 1);
    });

    test(
      'a stale yes is overtaken by a later no and the goal starts',
      () async {
        final setup = await _setup(rows: [_row(3, pregnant: true)]);

        final outcome = await _start(setup, pregnant: false);

        final rows = await setup.store.screenings();
        expect(outcome, SetupOutcome.started);
        expect(rows.first.pregnantOrBreastfeeding, isFalse);
        expect(rows.first.on, goalDay(12, 7));
      },
    );

    test('a male with a stored yes is asked and a yes again refuses', () async {
      final setup = await _setup(rows: [_row(3, pregnant: true)]);

      final outcome = await _start(setup, pregnant: true);

      expect(outcome, SetupOutcome.pregnancy);
      expect(await setup.store.goals(), isEmpty);
      expect(await setup.store.screenings(), hasLength(3));
    });
  });

  group('5. a null answer when asked', () {
    test('throws ArgumentError and writes nothing', () async {
      final setup = await _setup(sex: Sex.female);

      await expectLater(_start(setup), throwsArgumentError);

      expect(await setup.store.screenings(), hasLength(1));
      expect(await setup.store.goals(), isEmpty);
      expect(setup.revision, 0);
    });

    test('a male with a stored yes is asked too', () async {
      final setup = await _setup(rows: [_row(3, pregnant: true)]);

      await expectLater(_start(setup), throwsArgumentError);

      expect(await setup.store.screenings(), hasLength(2));
      expect(await setup.store.goals(), isEmpty);
    });
  });

  group('6. the reference weight', () {
    test('58.5 and 78.5 throw ArgumentError and write nothing', () async {
      for (final reference in [58.5, 78.5]) {
        final setup = await _setup();

        await expectLater(
          _start(setup, referenceKg: reference),
          throwsArgumentError,
        );

        expect(await setup.store.goals(), isEmpty);
        expect(setup.revision, 0);
      }
    });

    test('74.2 and both bounds pass, with no step rule', () async {
      for (final reference in [74.2, 59.0, 78.0]) {
        final setup = await _setup();

        final outcome = await _start(setup, referenceKg: reference);

        expect(outcome, SetupOutcome.started);
        expect((await setup.store.active())!.referenceKg, reference);
      }
    });

    test('a pound value converted to kilograms passes', () async {
      final setup = await _setup();
      const reference = 160 * 0.45359237;

      final outcome = await _start(setup, referenceKg: reference);

      expect(outcome, SetupOutcome.started);
      expect((await setup.store.active())!.referenceKg, reference);
    });

    test('a bad reference writes no pregnancy row either', () async {
      final setup = await _setup(sex: Sex.female);

      await expectLater(
        _start(setup, referenceKg: 58.5, pregnant: false),
        throwsArgumentError,
      );

      expect(await setup.store.screenings(), hasLength(1));
      expect(await setup.store.goals(), isEmpty);
      expect(setup.revision, 0);
    });
  });

  group('7. not allowed', () {
    test('a null trend writes nothing', () async {
      final setup = await _setup(trendKg: null);

      final outcome = await _start(setup);

      expect(outcome, SetupOutcome.notAllowed);
      expect(await setup.store.goals(), isEmpty);
      expect(setup.revision, 0);
    });

    test('soft mode on writes nothing', () async {
      final setup = await _setup(
        seedNo: false,
        rows: [_row(1, softMode: true)],
      );

      final outcome = await _start(setup);

      expect(outcome, SetupOutcome.notAllowed);
      expect(await setup.store.goals(), isEmpty);
      expect(await setup.store.screenings(), hasLength(1));
      expect(setup.revision, 0);
    });

    test('Goals off writes nothing', () async {
      final setup = await _setup(modules: const {ModuleId.body});

      final outcome = await _start(setup);

      expect(outcome, SetupOutcome.notAllowed);
      expect(await setup.store.goals(), isEmpty);
      expect(setup.revision, 0);
    });

    test('demo mode writes nothing, not even a pregnancy row', () async {
      final setup = await _setup(sex: Sex.female, demo: true);

      final outcome = await _start(setup, pregnant: false);

      expect(outcome, SetupOutcome.notAllowed);
      expect(await setup.store.goals(), isEmpty);
      expect(await setup.store.screenings(), hasLength(1));
      expect(setup.revision, 0);
    });

    test('a next step other than setup (never asked) writes nothing', () async {
      final setup = await _setup(seedNo: false);

      final outcome = await _start(setup);

      expect(outcome, SetupOutcome.notAllowed);
      expect(await setup.store.goals(), isEmpty);
      expect(setup.revision, 0);
    });

    test('a block such as a BMI under the floor writes nothing', () async {
      final setup = await _setup(trendKg: 50);

      final outcome = await _start(setup);

      expect(outcome, SetupOutcome.notAllowed);
      expect(await setup.store.goals(), isEmpty);
      expect(setup.revision, 0);
    });
  });

  group('8. an active goal', () {
    test('gives alreadyActive and writes nothing', () async {
      final setup = await _setup(draft: goalDraft());
      final before = await setup.store.active();

      final outcome = await _start(setup, referenceKg: 74);

      expect(outcome, SetupOutcome.alreadyActive);
      expectSameGoal(await setup.store.active(), before!);
      expect(await setup.store.goals(), hasLength(1));
      expect(setup.revision, 0);
    });

    test('a female with an active goal writes no pregnancy row', () async {
      final setup = await _setup(sex: Sex.female, draft: goalDraft());

      final outcome = await _start(setup, pregnant: false);

      expect(outcome, SetupOutcome.alreadyActive);
      expect(await setup.store.screenings(), hasLength(1));
      expect(setup.revision, 0);
    });

    test('a store whose start returns null gives alreadyActive', () async {
      final setup = await _setup(
        readStoreOf: (memory) => ProbeGoalStore(memory, startsNull: true),
      );

      final outcome = await _start(setup);

      expect(outcome, SetupOutcome.alreadyActive);
      expect(await setup.store.goals(), isEmpty);
    });
  });

  group('9. a throwing store', () {
    test('a start that throws is rethrown and the revision holds', () async {
      final setup = await _setup(
        readStoreOf: (memory) =>
            ProbeGoalStore(memory, startError: StateError('disk full')),
      );

      await expectLater(_start(setup), throwsStateError);

      expect(setup.revision, 0);
      expect(await setup.store.goals(), isEmpty);
    });

    test('a pregnancy write that throws is rethrown, no goal starts', () async {
      final setup = await _setup(
        sex: Sex.female,
        readStoreOf: (memory) => ProbeGoalStore(memory, screeningFailures: 1),
      );

      await expectLater(_start(setup, pregnant: false), throwsStateError);

      expect(setup.revision, 0);
      expect(await setup.store.goals(), isEmpty);
      expect(await setup.store.screenings(), hasLength(1));
    });
  });

  group('review focus 2: a double call', () {
    test('two concurrent starts store at most one goal', () async {
      final gate = Completer<void>();
      final setup = await _setup(
        readStoreOf: (memory) => ProbeGoalStore(memory, gate: gate),
      );
      final controller = setup.container.read(goalSetupControllerProvider);
      Future<SetupOutcome> call() => controller.start(
        pace: GoalPace.standard,
        referenceKg: null,
        pregnantOrBreastfeeding: null,
      );

      final first = call();
      final second = call();
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      final outcomes = await Future.wait([first, second]);

      expect(
        outcomes,
        unorderedEquals([SetupOutcome.started, SetupOutcome.alreadyActive]),
      );
      expect(await setup.store.goals(), hasLength(1));
      expect(await setup.store.screenings(), hasLength(1));
    });
  });
}
