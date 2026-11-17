import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/goals/application/goal_ender.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

import '../goal_fixtures.dart';

final LocalDate _today = goalDay(12, 7);

enum _Fault { writeThrows, writeFalse, readThrows }

final class _Faulty implements GoalStore {
  new(this.inner, this.fault);

  final InMemoryGoalStore inner;
  final _Fault fault;
  int writes = 0;

  @override
  Future<Goal?> active() async {
    if (fault == _Fault.readThrows) throw StateError('the goal was not read');
    return await inner.active();
  }

  @override
  Future<List<GoalWeek>> weeks(int goalId) => inner.weeks(goalId);

  @override
  Future<bool> setPhase(
    int goalId,
    GoalPhase phase, {
    required LocalDate since,
    LocalDate? until,
  }) async {
    writes++;
    if (fault == _Fault.writeThrows) throw StateError('not written');
    if (fault == _Fault.writeFalse) return false;
    return await inner.setPhase(goalId, phase, since: since, until: until);
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<GoalSetup> _rig({
  Set<ModuleId> modules = goalModules,
  GoalDraft? draft,
  bool demo = false,
  GoalStore Function(InMemoryGoalStore)? wrap,
  InMemoryGoalStore? store,
  DateTime? now,
  Override? weight,
}) async {
  final memory = store ?? InMemoryGoalStore();
  final setup = await setupGoals(
    now: now,
    modules: modules,
    draft: store == null ? draft : null,
    store: memory,
    readStore: wrap?.call(memory),
    weightOverride: weight,
    extraOverrides: [
      demoModeStoreProvider.overrideWithValue(
        InMemoryDemoModeStore(enabled: demo),
      ),
    ],
  );
  setup.container.listen(demoModeProvider, (_, _) {});
  return setup;
}

Future<bool> _maintainNow(GoalSetup setup) =>
    setup.container.read(goalEnderProvider.notifier).maintainNow();

Future<Goal> _goal(GoalSetup setup) async => (await setup.store.goals()).first;

List<DailyValue> _flat(LocalDate last, double kg) => [
  for (var i = 27; i >= 0; i--) (date: last.addDays(-i), value: kg),
];

Override _weightOf(List<DailyValue> days) => weightSummaryProvider.overrideWith(
  (ref) async => goalWeightSummary(days: days),
);

void main() {
  group('G11b2 criterion 1: maintain now on a block', () {
    test('returns true and moves the goal into maintenance', () async {
      final setup = await _rig(draft: goalDraft());

      final done = await _maintainNow(setup);

      expect(done, isTrue);
      expect((await _goal(setup)).phase, GoalPhase.maintenance);
    });

    test('maintenance starts today and lasts until today plus 27', () async {
      final setup = await _rig(draft: goalDraft());

      await _maintainNow(setup);

      final goal = await _goal(setup);
      expect(goal.phaseSince, _today);
      expect(goal.phaseUntil, _today.addDays(27));
    });

    test('bumps the data revision once', () async {
      final setup = await _rig(draft: goalDraft());
      final before = setup.revision;

      await _maintainNow(setup);

      expect(setup.revision, before + 1);
    });

    test('keeps the levers and the block start', () async {
      final setup = await _rig(draft: goalDraft());
      final before = await _goal(setup);

      await _maintainNow(setup);

      final goal = await _goal(setup);
      expectSameLevers(goal.levers, before.levers);
      expect(goal.blockStartedOn, before.blockStartedOn);
      expect(goal.blockAnchorKg, before.blockAnchorKg);
    });

    test('started midweek, until is midweek too', () async {
      final setup = await _rig(draft: goalDraft(), now: goalAt(12, 9));

      await _maintainNow(setup);

      final goal = await _goal(setup);
      expect(goal.phaseSince, goalDay(12, 9));
      expect(goal.phaseUntil, goalDay(12, 9).addDays(27));
    });
  });

  group('G11b2 criterion 2: maintain now refuses and writes nothing', () {
    Future<void> expectRefused(GoalSetup setup) async {
      final before = (await setup.store.goals()).toList();
      final revision = setup.revision;

      final done = await _maintainNow(setup);

      expect(done, isFalse);
      expect(setup.revision, revision);
      final after = await setup.store.goals();
      expect(after.length, before.length);
      for (var i = 0; i < after.length; i++) {
        expectSameGoal(after[i], before[i]);
      }
    }

    test('Goals off', () async {
      await expectRefused(await _rig(modules: {}, draft: goalDraft()));
    });

    test('demo mode', () async {
      await expectRefused(await _rig(demo: true, draft: goalDraft()));
    });

    test('no goal', () async {
      await expectRefused(await _rig());
    });

    test('a getFitter goal', () async {
      await expectRefused(
        await _rig(draft: goalDraft(kind: GoalKind.getFitter)),
      );
    });

    test('a sleepBetter goal', () async {
      await expectRefused(
        await _rig(draft: goalDraft(kind: GoalKind.sleepBetter)),
      );
    });

    test('a paused goal', () async {
      final setup = await _rig(draft: goalDraft());
      await setup.store.setPhase(
        1,
        GoalPhase.paused,
        since: _today,
        until: _today.addDays(14),
      );
      await expectRefused(setup);
    });

    test('a goal already in maintenance', () async {
      final setup = await _rig(draft: goalDraft());
      await setup.store.setPhase(
        1,
        GoalPhase.maintenance,
        since: _today.addDays(-3),
        until: _today.addDays(24),
      );
      await expectRefused(setup);
    });

    test('a goal with no levers', () async {
      await expectRefused(await _rig(draft: goalDraft(levers: const [])));
    });

    test('Body off', () async {
      await expectRefused(
        await _rig(modules: {ModuleId.goals}, draft: goalDraft()),
      );
    });
  });

  group('G11b2 criterion 3: a failing store is refused, not thrown', () {
    final logs = <String>[];
    late DebugPrintCallback printed;

    setUp(() {
      logs.clear();
      printed = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    });

    tearDown(() => debugPrint = printed);

    for (final (name, fault) in [
      ('setPhase throws', _Fault.writeThrows),
      ('the read throws', _Fault.readThrows),
    ]) {
      test('$name: false, logged, goal and revision unchanged', () async {
        final setup = await _rig(
          draft: goalDraft(),
          wrap: (memory) => _Faulty(memory, fault),
        );
        final before = await _goal(setup);
        final revision = setup.revision;

        final done = await _maintainNow(setup);

        expect(done, isFalse);
        expect(logs, isNotEmpty);
        expectSameGoal(await _goal(setup), before);
        expect(setup.revision, revision);
      });
    }

    test(
      'setPhase returns false: false, goal and revision unchanged',
      () async {
        late _Faulty faulty;
        final setup = await _rig(
          draft: goalDraft(),
          wrap: (memory) => faulty = _Faulty(memory, _Fault.writeFalse),
        );
        final before = await _goal(setup);
        final revision = setup.revision;

        final done = await _maintainNow(setup);

        expect(done, isFalse);
        expect(faulty.writes, 1);
        expectSameGoal(await _goal(setup), before);
        expect(setup.revision, revision);
      },
    );
  });

  group('G11b2 review focus: the move beside the weekly review', () {
    test('a pending proposal lapses unanswered at the move', () async {
      final setup = await _rig(draft: goalDraft());
      await setup.reviewer.reviewDueWeek();
      final before = (await setup.weeks()).single;
      expect(before.change, isNotNull);

      await _maintainNow(setup);

      final row = (await setup.weeks()).single;
      expect(row.answer, isNull);
      expectSameLevers((await _goal(setup)).levers, const [
        strengthLever,
        sleepLever,
        stepsLever,
      ]);
    });

    test(
      'the Monday review after the move writes a row with no change',
      () async {
        final setup = await _rig(draft: goalDraft());
        await _maintainNow(setup);

        await setup.reviewer.reviewDueWeek();

        final row = (await setup.weeks()).single;
        expect(row.inputs.maintenance, isTrue);
        expect(row.change, isNull);
      },
    );

    test(
      'a Monday inside a midweek maintenance still writes its row',
      () async {
        final store = InMemoryGoalStore();
        final midweek = await _rig(store: store, now: goalAt(12, 9));
        await store.start(goalDraft());
        await _maintainNow(midweek);

        final monday = await _rig(store: store, now: goalAt(12, 14));
        await monday.reviewer.reviewDueWeek();

        final rows = await store.weeks(1);
        expect(rows.map((row) => row.monday), [goalDay(12, 14)]);
        expect(rows.single.inputs.maintenance, isTrue);
      },
    );
  });

  group('G11b2 criterion 10: the next block follows a move', () {
    Future<GoalSetup> after(DateTime now) async {
      final store = InMemoryGoalStore();
      await store.start(goalDraft());
      final move = await _rig(store: store);
      expect(await _maintainNow(move), isTrue);
      return await _rig(
        store: store,
        now: now,
        weight: _weightOf(_flat(goalDay(12, 7).addDays(27), 71.9)),
      );
    }

    test('the day after until starts the block', () async {
      final setup = await after(DateTime(2027, 1, 4, 8, 10));

      expect(await setup.reviewer.startDueBlock(), isTrue);

      final goal = (await setup.store.active())!;
      expect(goal.phase, GoalPhase.block);
      expect(goal.blockStartedOn, const LocalDate(2027, 1, 4));
      expect(goal.blockAnchorKg, isNotNull);
    });

    test('the last day of maintenance starts nothing', () async {
      final setup = await after(DateTime(2027, 1, 3, 8, 10));

      expect(await setup.reviewer.startDueBlock(), isFalse);
      expect((await setup.store.active())!.phase, GoalPhase.maintenance);
    });
  });
}
