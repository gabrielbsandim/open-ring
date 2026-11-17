import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/domain/review_inputs.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';

import '../goal_fixtures.dart';

const int _bedAt2330 = 23 * 60 + 30;

const Lever _strength = strengthLever;
const Lever _sleep = sleepLever;
const Lever _steps = stepsLever;

final class _GatedStore implements GoalStore {
  new(this.inner);

  final InMemoryGoalStore inner;
  final gate = Completer<void>();
  bool reachedStartBlock = false;

  @override
  Future<Goal?> active() => inner.active();

  @override
  Future<bool> startBlock(
    int goalId, {
    required LocalDate on,
    required double? anchorKg,
    List<Lever>? levers,
  }) async {
    reachedStartBlock = true;
    await gate.future;
    return await inner.startBlock(
      goalId,
      on: on,
      anchorKg: anchorKg,
      levers: levers,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('the store was read: ${invocation.memberName}');
}

Future<GoalSetup> _ready({
  DateTime? now,
  Set<ModuleId> modules = goalModules,
  int extraWeighIns = 0,
}) => setupGoals(
  now: now,
  modules: modules,
  draft: goalDraft(),
  extraWeighIns: extraWeighIns,
);

List<(LeverKind, int, int)> _levers(ReviewInputs inputs) => [
  for (final week in inputs.levers)
    (week.lever.kind, week.lever.target, week.achieved),
];

ReviewInputs _pendingInputs({
  CheckInEnergy? energy,
  CheckInEnergy? energyPrevious,
}) =>
    f1With(energy: energy, energyPrevious: energyPrevious, foodOrWeight: null);

Future<GoalSetup> _pausableSetup() async {
  final setup = await _ready();
  final previous = _pendingInputs(
    energy: CheckInEnergy.low,
    energyPrevious: CheckInEnergy.normal,
  );
  final current = _pendingInputs(energyPrevious: CheckInEnergy.low);
  await setup.store.addWeek(
    1,
    monday: goalDay(11, 30),
    inputs: previous,
    review: reviewWeek(previous),
  );
  await setup.store.addWeek(
    1,
    monday: goalDay(12, 7),
    inputs: current,
    review: reviewWeek(current),
  );
  return setup;
}

GoalWeekData _data() => GoalWeekData(
  steps: {for (final day in goalStepDays().values) day.date: day.steps},
  nights: goalNights(),
  strengthDays: effortStrengthDays(goalSessions()),
);

Lever _starting(GoalKind kind, LocalDate end) =>
    startingLever(kind, leverBaseline(_data(), end: end))!;

Override _weightOf(List<DailyValue> days) => weightSummaryProvider.overrideWith(
  (ref) async => goalWeightSummary(days: days),
);

Override _noWeight() => weightSummaryProvider.overrideWith((ref) async => null);

Override _throwingWeight() => weightSummaryProvider.overrideWith(
  (ref) async => throw StateError('the weight was read'),
);

Override _nightsOf(Iterable<LocalDate> dates, {required int wake}) =>
    sleepNightsProvider.overrideWith(
      (ref) async => {
        for (final date in dates)
          date: goalNight(date, onset: _bedAt2330, wake: wake),
      },
    );

Future<GoalSetup> _withoutLevers({
  GoalKind kind = GoalKind.loseFat,
  DateTime? now,
  Set<ModuleId> modules = goalModules,
  Override? stepsOverride,
  Override? nightsOverride,
  Override? weightOverride,
}) => setupGoals(
  now: now,
  modules: modules,
  draft: goalDraft(kind: kind, levers: const []),
  stepsOverride: stepsOverride,
  nightsOverride: nightsOverride,
  weightOverride: weightOverride,
);

Future<GoalSetup> _pausedUntil(
  LocalDate? until, {
  GoalKind kind = GoalKind.getFitter,
  DateTime? now,
  int extraWeighIns = 0,
}) async {
  final setup = await setupGoals(
    now: now,
    draft: goalDraft(kind: kind),
    extraWeighIns: extraWeighIns,
  );
  await setup.store.setPhase(
    1,
    GoalPhase.paused,
    since: goalDay(12, 7),
    until: until,
  );
  return setup;
}

void main() {
  group('G5b2b1 case 7: a block start for lose fat with no levers', () {
    final asOf = weightSnapshot(daily: goalWeights(), asOf: goalDay(12, 7));

    test('the fixture weight has a ready rate and a trend', () {
      expect(asOf.rate, isA<WeightRateReady>());
      expect(asOf.trendKg, isNotNull);
    });

    test('is true', () async {
      final setup = await _withoutLevers();

      expect(await setup.reviewer.startDueBlock(), isTrue);
    });

    test('starts the block on the day', () async {
      final setup = await _withoutLevers();

      await setup.reviewer.startDueBlock();

      final goal = (await setup.store.active())!;
      expect(goal.phase, GoalPhase.block);
      expect(goal.blockStartedOn, goalDay(12, 7));
      expect(goal.phaseSince, goalDay(12, 7));
      expect(goal.phaseUntil, isNull);
    });

    test('anchors the block on the weight trend of the day', () async {
      final setup = await _withoutLevers();

      await setup.reviewer.startDueBlock();

      expect((await setup.store.active())!.blockAnchorKg, asOf.trendKg);
    });

    test('stores the starting lever read up to the day before', () async {
      final setup = await _withoutLevers();

      await setup.reviewer.startDueBlock();

      final levers = (await setup.store.active())!.levers;
      expectSameLevers(levers, [_starting(GoalKind.loseFat, goalDay(12, 6))]);
      expect(levers.single.kind, LeverKind.strengthDays);
    });

    test('bumps the data revision once', () async {
      final setup = await _withoutLevers();
      final before = setup.revision;

      await setup.reviewer.startDueBlock();

      expect(setup.revision, before + 1);
    });

    test('a second call is false and does not bump', () async {
      final setup = await _withoutLevers();
      await setup.reviewer.startDueBlock();
      final before = setup.revision;

      final second = await setup.reviewer.startDueBlock();

      expect(second, isFalse);
      expect(setup.revision, before);
    });
  });

  group('G5b2b1 case 8: a block start that does not happen', () {
    Future<void> expectNothingStarted(GoalSetup setup, Goal before) async {
      expect(await setup.reviewer.startDueBlock(), isFalse);
      expectSameGoal(await setup.store.active(), before);
      expect(setup.revision, 0);
    }

    test('five weigh-in days are not a ready rate', () async {
      final setup = await _withoutLevers(
        weightOverride: _weightOf(goalWeights().skip(23).toList()),
      );

      await expectNothingStarted(setup, (await setup.store.active())!);
    });

    test('no weight summary gives false', () async {
      final setup = await _withoutLevers(weightOverride: _noWeight());

      await expectNothingStarted(setup, (await setup.store.active())!);
    });

    test('Body off gives false and the weight is not read', () async {
      final setup = await _withoutLevers(
        modules: const {ModuleId.goals},
        weightOverride: _throwingWeight(),
      );

      await expectNothingStarted(setup, (await setup.store.active())!);
    });

    test('a goal that has levers gives false', () async {
      final setup = await _ready();

      await expectNothingStarted(setup, (await setup.store.active())!);
    });

    test('Goals off gives false and the store is not read', () async {
      final setup = await setupGoals(
        modules: const {},
        readStore: UnreadableGoalStore(),
      );

      expect(await setup.reviewer.startDueBlock(), isFalse);
      expect(setup.revision, 0);
    });

    test('no goal gives false and no bump', () async {
      final setup = await setupGoals();

      expect(await setup.reviewer.startDueBlock(), isFalse);
      expect(await setup.store.count(), 0);
      expect(setup.revision, 0);
    });
  });

  group('G5b2b1 case 9: get fitter with no levers', () {
    Future<GoalSetup> started() async {
      final setup = await _withoutLevers(
        kind: GoalKind.getFitter,
        weightOverride: _throwingWeight(),
      );
      await setup.reviewer.startDueBlock();
      return setup;
    }

    test('is true and the weight is never read', () async {
      final setup = await _withoutLevers(
        kind: GoalKind.getFitter,
        weightOverride: _throwingWeight(),
      );

      expect(await setup.reviewer.startDueBlock(), isTrue);
    });

    test('starts the block on the day with a null anchor', () async {
      final setup = await started();

      final goal = (await setup.store.active())!;
      expect(goal.blockStartedOn, goalDay(12, 7));
      expect(goal.blockAnchorKg, isNull);
    });

    test('stores the starting lever of the fixture data', () async {
      final setup = await started();

      expectSameLevers((await setup.store.active())!.levers, [
        _starting(GoalKind.getFitter, goalDay(12, 6)),
      ]);
    });
  });

  group('G5b2b1 case 10: sleep better', () {
    test('with no nights gives false and no bump', () async {
      final setup = await _withoutLevers(
        kind: GoalKind.sleepBetter,
        nightsOverride: _nightsOf(const [], wake: 405),
      );
      final before = (await setup.store.active())!;

      final started = await setup.reviewer.startDueBlock();

      expect(started, isFalse);
      expectSameGoal(await setup.store.active(), before);
      expect(setup.revision, 0);
    });

    test('with seven nights starts on the median wake time', () async {
      final setup = await _withoutLevers(
        kind: GoalKind.sleepBetter,
        nightsOverride: _nightsOf([
          for (var d = 0; d < 7; d++) goalDay(11, 30).addDays(d),
        ], wake: 405),
      );

      final started = await setup.reviewer.startDueBlock();

      final levers = (await setup.store.active())!.levers;
      expect(started, isTrue);
      expect(
        [for (final lever in levers) (lever.kind, lever.target)],
        [(LeverKind.wakeTime, 405)],
      );
    });
  });

  group('G5b2b1 case 11: after a dated pause', () {
    test('on the last day of the pause nothing starts', () async {
      final setup = await _pausedUntil(goalDay(12, 20), now: goalAt(12, 20));
      final before = (await setup.store.active())!;

      final started = await setup.reviewer.startDueBlock();

      expect(started, isFalse);
      expectSameGoal(await setup.store.active(), before);
      expect(setup.revision, 0);
    });

    test('the next day starts a block with no end', () async {
      final setup = await _pausedUntil(goalDay(12, 20), now: goalAt(12, 21));

      final started = await setup.reviewer.startDueBlock();

      final goal = (await setup.store.active())!;
      expect(started, isTrue);
      expect(goal.phase, GoalPhase.block);
      expect(goal.blockStartedOn, goalDay(12, 21));
      expect(goal.phaseSince, goalDay(12, 21));
      expect(goal.phaseUntil, isNull);
      expect(goal.blockAnchorKg, isNull);
    });

    test('the next day keeps the levers', () async {
      final setup = await _pausedUntil(goalDay(12, 20), now: goalAt(12, 21));

      await setup.reviewer.startDueBlock();

      expectSameLevers((await setup.store.active())!.levers, const [
        _strength,
        _sleep,
        _steps,
      ]);
    });

    test('the next day bumps the data revision once', () async {
      final setup = await _pausedUntil(goalDay(12, 20), now: goalAt(12, 21));

      await setup.reviewer.startDueBlock();

      expect(setup.revision, 1);
    });
  });

  group('G5b2b1 case 12: lose fat after a dated pause', () {
    test('13 weigh-in days over 12 are still building', () async {
      final setup = await _pausedUntil(
        goalDay(12, 20),
        kind: GoalKind.loseFat,
        now: goalAt(12, 21),
      );
      final before = (await setup.store.active())!;

      final started = await setup.reviewer.startDueBlock();

      final snapshot = weightSnapshot(
        daily: goalWeights(),
        asOf: goalDay(12, 21),
      );
      expect(snapshot.rate, isA<WeightRateBuilding>());
      expect(started, isFalse);
      expectSameGoal(await setup.store.active(), before);
      expect(setup.revision, 0);
    });

    test('15 more weigh-ins give a ready rate and the block starts', () async {
      final setup = await _pausedUntil(
        goalDay(12, 20),
        kind: GoalKind.loseFat,
        now: goalAt(12, 21),
        extraWeighIns: 15,
      );

      final started = await setup.reviewer.startDueBlock();

      final snapshot = weightSnapshot(
        daily: goalWeightSummary(extraDays: 15).daily,
        asOf: goalDay(12, 21),
      );
      final goal = (await setup.store.active())!;
      expect(snapshot.rate, isA<WeightRateReady>());
      expect(started, isTrue);
      expect(goal.blockStartedOn, goalDay(12, 21));
      expect(goal.blockAnchorKg, snapshot.trendKg);
      expect(goal.blockAnchorKg, isNotNull);
      expect(goal.phaseUntil, isNull);
    });
  });

  group('G5b2b1 case 13: a pause with no end', () {
    test('is never ended by the clock', () async {
      final setup = await _pausedUntil(null, now: DateTime(2027, 3, 1, 8, 10));
      final before = (await setup.store.active())!;

      final started = await setup.reviewer.startDueBlock();

      expect(started, isFalse);
      expectSameGoal(await setup.store.active(), before);
      expect(setup.revision, 0);
    });
  });

  group('G5b2b1 sources that fail', () {
    test('activity days that throw stop the block start', () async {
      final setup = await _withoutLevers(
        kind: GoalKind.getFitter,
        stepsOverride: activityDaysProvider.overrideWith(
          (ref) async => throw StateError('no activity'),
        ),
      );
      final before = (await setup.store.active())!;

      await expectLater(
        setup.reviewer.startDueBlock(),
        throwsA(isA<StateError>()),
      );

      expectSameGoal(await setup.store.active(), before);
      expect(setup.revision, 0);
    });

    test('a weight summary that throws stops a lose fat start', () async {
      final setup = await _withoutLevers(weightOverride: _throwingWeight());
      final before = (await setup.store.active())!;

      await expectLater(
        setup.reviewer.startDueBlock(),
        throwsA(isA<StateError>()),
      );

      expectSameGoal(await setup.store.active(), before);
      expect(setup.revision, 0);
    });

    test('a container disposed while the block is written does not '
        'throw', () async {
      final inner = InMemoryGoalStore();
      final gated = _GatedStore(inner);
      final setup = await setupGoals(
        draft: goalDraft(kind: GoalKind.getFitter, levers: const []),
        store: inner,
        readStore: gated,
      );
      final pending = setup.reviewer.startDueBlock();
      await pumpEventQueue();
      expect(gated.reachedStartBlock, isTrue);

      setup.container.dispose();
      gated.gate.complete();

      await expectLater(pending, completes);
      expect((await inner.active())!.blockStartedOn, goalDay(12, 7));
    });
  });

  group('G5b2b1 case 14: no review while there are no levers', () {
    test('the week is the fourth, which a goal with levers reviews', () {
      expect(goalWeekNumber(start: goalDay(11, 16), today: goalDay(12, 7)), 4);
    });

    test('gives null, writes no row and does not bump', () async {
      final setup = await _withoutLevers();

      final review = await setup.reviewer.reviewDueWeek();

      expect(review, isNull);
      expect(await setup.weeks(), isEmpty);
      expect(setup.revision, 0);
    });
  });

  group('G5b2b1 case 15: a review that ends the goal', () {
    Future<GoalSetup> pregnant() async {
      final setup = await _ready();
      await setup.store.addScreening(
        const GoalScreening(
          on: LocalDate(2026, 11, 16),
          softMode: null,
          pregnantOrBreastfeeding: true,
        ),
      );
      return setup;
    }

    test('returns rule 1', () async {
      final setup = await pregnant();

      final review = await setup.reviewer.reviewDueWeek();

      expect(review?.rule, ReviewRule.end);
      expect(review?.action, ReviewAction.end);
    });

    test('ends the goal on the Monday as a protection', () async {
      final setup = await pregnant();

      await setup.reviewer.reviewDueWeek();

      final goal = (await setup.store.goals()).single;
      expect(goal.phase, GoalPhase.ended);
      expect(goal.endedOn, goalDay(12, 7));
      expect(goal.endReason, GoalEndReason.protection);
    });

    test('writes one row and bumps once', () async {
      final setup = await pregnant();
      final before = setup.revision;

      await setup.reviewer.reviewDueWeek();

      expect(await setup.weeks(), hasLength(1));
      expect(setup.revision, before + 1);
    });

    test('reads the active goal as null after the bump', () async {
      final setup = await pregnant();
      setup.container.listen(activeGoalProvider, (_, _) {});
      expect(await setup.container.read(activeGoalProvider.future), isNotNull);

      await setup.reviewer.reviewDueWeek();

      expect(await setup.container.read(activeGoalProvider.future), isNull);
    });
  });

  group('G5b2b1 case 16: the check-in that pauses', () {
    test('pauses the goal from the Monday with no end', () async {
      final setup = await _pausableSetup();

      await setup.reviewer.checkIn(goalDay(12, 7), energy: CheckInEnergy.low);

      final goal = (await setup.store.active())!;
      expect(goal.phase, GoalPhase.paused);
      expect(goal.phaseSince, goalDay(12, 7));
      expect(goal.phaseUntil, isNull);
    });
  });

  group('case 8: the review of the closed week', () {
    test('writes one row on the Monday', () async {
      final setup = await _ready();

      final review = await setup.reviewer.reviewDueWeek();

      final weeks = await setup.weeks();
      expect(weeks, hasLength(1));
      expect(weeks.single.monday, goalDay(12, 7));
      expect(review, isNotNull);
    });

    test('counts the fourth week with 2, 6 and 5 achieved', () async {
      final setup = await _ready();

      await setup.reviewer.reviewDueWeek();

      final inputs = (await setup.weeks()).single.inputs;
      expect(inputs.week, 4);
      expect(_levers(inputs), [
        (LeverKind.strengthDays, 2, 2),
        (LeverKind.sleepWindow, 690, 6),
        (LeverKind.steps, 9000, 5),
      ]);
    });

    test('reads the seven closed readiness values', () async {
      final setup = await _ready();

      await setup.reviewer.reviewDueWeek();

      final inputs = (await setup.weeks()).single.inputs;
      expect(inputs.readiness, closedWeekReadiness);
    });

    test('reads the baseline over the days that end on the Sunday', () async {
      final setup = await _ready();

      await setup.reviewer.reviewDueWeek();

      final baseline = (await setup.weeks()).single.inputs.baseline;
      expect(baseline.stepsMedian14, 8000);
      expect(baseline.bedMedian, 705);
      expect(baseline.wakeMedian, 405);
      expect(baseline.effortMean4Weeks, isNull);
      expect(baseline.strengthDaysUsual, 1);
    });

    test('rates the weight as of the Sunday with a bmi from 178 cm', () async {
      final setup = await _ready();

      await setup.reviewer.reviewDueWeek();

      final inputs = (await setup.weeks()).single.inputs;
      expect(inputs.bodyOn, isTrue);
      expect(inputs.rate?.percent, closeTo(0.4427, 0.0005));
      expect(inputs.bmi, closeTo(24.954, 0.0005));
    });

    test('is the build rule with steps from 9000 to 10000', () async {
      final setup = await _ready();

      final review = await setup.reviewer.reviewDueWeek();

      final week = (await setup.weeks()).single;
      expect(week.rule, ReviewRule.build);
      expect(week.action, ReviewAction.nextStep);
      expect(week.change?.kind, LeverKind.steps);
      expect(week.change?.from, 9000);
      expect(week.change?.to, 10000);
      expect(review?.rule, ReviewRule.build);
      expect(review?.change?.to, 10000);
    });

    test('bumps the data revision once', () async {
      final setup = await _ready();
      final before = setup.revision;

      await setup.reviewer.reviewDueWeek();

      expect(setup.revision, before + 1);
    });
  });

  group('case 9: the week is written once', () {
    test('a second call writes nothing and does not bump', () async {
      final setup = await _ready();
      final before = setup.revision;

      final first = await setup.reviewer.reviewDueWeek();
      final second = await setup.reviewer.reviewDueWeek();

      expect(first, isNotNull);
      expect(second, isNull);
      expect(await setup.weeks(), hasLength(1));
      expect(setup.revision, before + 1);
    });

    test('two calls at once write one row and bump once', () async {
      final setup = await _ready();
      final before = setup.revision;

      final results = await Future.wait([
        setup.reviewer.reviewDueWeek(),
        setup.reviewer.reviewDueWeek(),
      ]);

      expect(results.nonNulls, hasLength(1));
      expect(await setup.weeks(), hasLength(1));
      expect(setup.revision, before + 1);
    });
  });

  group('case 10: the week written later in the week', () {
    test('reads the same inputs on Thursday with newer weigh-ins', () async {
      final monday = await _ready();
      final thursday = await _ready(now: goalAt(12, 10), extraWeighIns: 4);

      await monday.reviewer.reviewDueWeek();
      await thursday.reviewer.reviewDueWeek();

      expectSameInputs(
        (await thursday.weeks()).single.inputs,
        (await monday.weeks()).single.inputs,
      );
    });

    test('still writes the row on the Monday of that week', () async {
      final thursday = await _ready(now: goalAt(12, 10), extraWeighIns: 4);

      await thursday.reviewer.reviewDueWeek();

      expect((await thursday.weeks()).single.monday, goalDay(12, 7));
    });
  });

  group('case 11: a gap in the history', () {
    test(
      'writes the new Monday, not the missed one, with no previous',
      () async {
        final store = InMemoryGoalStore();
        final first = await setupGoals(draft: goalDraft(), store: store);
        await first.reviewer.reviewDueWeek();
        final later = await setupGoals(now: goalAt(12, 21), store: store);
        final before = later.revision;

        await later.reviewer.reviewDueWeek();

        final weeks = await store.weeks(1);
        expect(
          [for (final week in weeks) week.monday],
          [goalDay(12, 7), goalDay(12, 21)],
        );
        expect(weeks.last.inputs.adherencePrevious, isNull);
        expect(later.revision, before + 1);
      },
    );
  });

  group('case 12: nothing to review', () {
    test('Goals off gives null, no read of the store and no bump', () async {
      final setup = await setupGoals(
        modules: const {},
        readStore: UnreadableGoalStore(),
      );

      final review = await setup.reviewer.reviewDueWeek();

      expect(review, isNull);
      expect(setup.revision, 0);
    });

    test('no goal gives null, no row and no bump', () async {
      final setup = await setupGoals();

      final review = await setup.reviewer.reviewDueWeek();

      expect(review, isNull);
      expect(await setup.store.count(), 0);
      expect(setup.revision, 0);
    });

    test('a paused goal gives null, no row and no bump', () async {
      final setup = await _ready();
      await setup.store.setPhase(
        1,
        GoalPhase.paused,
        since: goalDay(12, 1),
        until: goalDay(12, 28),
      );

      final review = await setup.reviewer.reviewDueWeek();

      expect(review, isNull);
      expect(await setup.weeks(), isEmpty);
      expect(setup.revision, 0);
    });

    test('a goal started on 12-01 has no review on 12-07', () async {
      final setup = await setupGoals(
        draft: goalDraft(startedOn: goalDay(12, 1)),
      );

      final review = await setup.reviewer.reviewDueWeek();

      expect(review, isNull);
      expect(await setup.weeks(), isEmpty);
      expect(setup.revision, 0);
    });

    test('the same goal is reviewed on 12-14', () async {
      final setup = await setupGoals(
        now: goalAt(12, 14),
        draft: goalDraft(startedOn: goalDay(12, 1)),
      );

      final review = await setup.reviewer.reviewDueWeek();

      expect(review, isNotNull);
      expect((await setup.weeks()).single.monday, goalDay(12, 14));
    });
  });

  group('case 13: a source that fails', () {
    test('activity days that throw make the call throw and write '
        'nothing', () async {
      final setup = await setupGoals(
        draft: goalDraft(),
        stepsOverride: activityDaysProvider.overrideWith(
          (ref) async => throw StateError('no activity'),
        ),
      );

      await expectLater(
        setup.reviewer.reviewDueWeek(),
        throwsA(isA<StateError>()),
      );

      expect(await setup.weeks(), isEmpty);
      expect(setup.revision, 0);
    });

    test('a weight summary that throws does not stop a sleepBetter '
        'goal', () async {
      final setup = await setupGoals(
        draft: goalDraft(kind: GoalKind.sleepBetter, levers: const [_sleep]),
        weightOverride: weightSummaryProvider.overrideWith(
          (ref) async => throw StateError('no weight'),
        ),
      );

      final review = await setup.reviewer.reviewDueWeek();

      expect(review, isNotNull);
      final inputs = (await setup.weeks()).single.inputs;
      expect(inputs.kind, GoalKind.sleepBetter);
      expect(inputs.rate, isNull);
      expect(inputs.bmi, isNull);
    });
  });

  group('case 14: Body off', () {
    test('gives no rate, no bmi and a false body flag', () async {
      final setup = await _ready(modules: const {ModuleId.goals});

      await setup.reviewer.reviewDueWeek();

      final inputs = (await setup.weeks()).single.inputs;
      expect(inputs.rate, isNull);
      expect(inputs.bmi, isNull);
      expect(inputs.bodyOn, isFalse);
    });
  });

  group('case 15: the check-in', () {
    test('returns the pause and bumps once', () async {
      final setup = await _pausableSetup();
      final before = setup.revision;

      final review = await setup.reviewer.checkIn(
        goalDay(12, 7),
        energy: CheckInEnergy.low,
      );

      expect(review?.rule, ReviewRule.pauseCheckIn);
      expect(review?.action, ReviewAction.pause);
      expect(setup.revision, before + 1);
    });

    test('a refused check-in does not bump', () async {
      final setup = await _pausableSetup();
      await setup.reviewer.checkIn(goalDay(12, 7), energy: CheckInEnergy.low);
      final before = setup.revision;

      final again = await setup.reviewer.checkIn(
        goalDay(12, 7),
        energy: CheckInEnergy.good,
      );

      expect(again, isNull);
      expect(setup.revision, before);
    });

    test('a check-in with no goal gives null and does not bump', () async {
      final setup = await setupGoals();

      final review = await setup.reviewer.checkIn(
        goalDay(12, 7),
        energy: CheckInEnergy.low,
      );

      expect(review, isNull);
      expect(setup.revision, 0);
    });
  });

  group('case 16: the review view', () {
    test('is null before any row is written', () async {
      final setup = await _ready();
      setup.container.listen(goalReviewProvider, (_, _) {});

      expect(await setup.container.read(goalReviewProvider.future), isNull);
    });

    test('holds the newest row and its replayed review', () async {
      final setup = await _ready();
      setup.container.listen(goalReviewProvider, (_, _) {});
      await setup.container.read(goalReviewProvider.future);

      await setup.reviewer.reviewDueWeek();

      final view = await setup.container.read(goalReviewProvider.future);
      expect(view?.week.monday, goalDay(12, 7));
      expect(view?.review.adherence, 1.0);
      expect(view?.review.rule, ReviewRule.build);
    });

    test('shows the amended rule after the check-in', () async {
      final setup = await _ready();
      final previous = _pendingInputs(
        energy: CheckInEnergy.low,
        energyPrevious: CheckInEnergy.normal,
      );
      await setup.store.addWeek(
        1,
        monday: goalDay(11, 30),
        inputs: previous,
        review: reviewWeek(previous),
      );
      setup.container.listen(goalReviewProvider, (_, _) {});
      await setup.reviewer.reviewDueWeek();
      final written = await setup.container.read(goalReviewProvider.future);

      await setup.reviewer.checkIn(goalDay(12, 7), energy: CheckInEnergy.low);

      final amended = await setup.container.read(goalReviewProvider.future);
      expect(written?.review.rule, ReviewRule.build);
      expect(amended?.review.rule, ReviewRule.pauseCheckIn);
      expect(amended?.week.inputs.energy, CheckInEnergy.low);
    });

    test('is null with Goals off', () async {
      final setup = await setupGoals(modules: const {});
      setup.container.listen(goalReviewProvider, (_, _) {});

      expect(await setup.container.read(goalReviewProvider.future), isNull);
    });

    test('is null with Goals off over a stored week', () async {
      final written = await _ready();
      await written.reviewer.reviewDueWeek();
      final setup = await setupGoals(modules: const {}, store: written.store);
      setup.container.listen(goalReviewProvider, (_, _) {});

      expect(await written.weeks(), hasLength(1));
      expect(await setup.container.read(goalReviewProvider.future), isNull);
    });
  });
}
