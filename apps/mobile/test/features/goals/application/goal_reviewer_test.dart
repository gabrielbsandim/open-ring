import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_reviewer.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/domain/review_inputs.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/today/application/readiness_trend.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../goal_fixtures.dart';

const Set<ModuleId> _both = {ModuleId.goals, ModuleId.body};
const _closedReadiness = [76, 72, 70, 68, 74, 71, 76];
const _otherDayReadiness = 40;
const int _bedAt2330 = 23 * 60 + 30;

const _strength = Lever(kind: LeverKind.strengthDays, target: 2);
const _sleep = Lever(kind: LeverKind.sleepWindow, target: 690);
const _steps = Lever(kind: LeverKind.steps, target: 9000);

LocalDate _day(int month, int day) => LocalDate(2026, month, day);

DateTime _at(int month, int day, [int hour = 8, int minute = 10]) =>
    DateTime(2026, month, day, hour, minute);

DateTime _utc(LocalDate date, int minuteOfDay) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).add(Duration(minutes: minuteOfDay));

SleepNight _night(LocalDate date, {required int onset, required int wake}) {
  final onsetDate = onset >= 720 ? date.addDays(-1) : date;
  return SleepNight([
    SleepSpan(
      start: _utc(onsetDate, onset),
      end: _utc(date, wake),
      phase: SleepPhase.light,
      utcOffset: Duration.zero,
    ),
  ]);
}

DailyActivity _activity(LocalDate date, int steps) => DailyActivity(
  date: date,
  steps: steps,
  activeKilocalories: 0,
  distanceMeters: 0,
);

EffortSession _session(LocalDate date) => (
  date: date,
  start: _utc(date, 480),
  end: _utc(date, 540),
  elapsed: const Duration(hours: 1),
  type: WorkoutType.strength,
  points: IntensityMinutes.none,
  load: const SessionLoad(
    byHeartRate: null,
    byRating: null,
    byDefault: 150,
    value: 150,
    source: LoadSource.typeDefault,
  ),
  rating: null,
  strength: true,
);

// The closed week is that of case 13 of the review inputs; the other days are
// chosen so the baseline medians are 8000, 705, 405 and a usual 1 strength day.
Map<LocalDate, DailyActivity> _stepDays() => {
  for (var d = 23; d <= 29; d++) _day(11, d): _activity(_day(11, d), 7500),
  for (final (date, steps) in [
    (_day(11, 30), 9000),
    (_day(12, 1), 9500),
    (_day(12, 2), 10000),
    (_day(12, 3), 9100),
    (_day(12, 4), 12000),
    (_day(12, 5), 8500),
    (_day(12, 6), 8999),
    (_day(12, 7), 20000),
  ])
    date: _activity(date, steps),
};

Map<LocalDate, SleepNight> _nights() => {
  for (var d = 23; d <= 29; d++)
    _day(11, d): _night(_day(11, d), onset: 23 * 60 + 45, wake: 405),
  for (var d = 1; d <= 7; d++)
    _day(12, d): _night(_day(12, d), onset: 23 * 60 + 30, wake: 420),
};

List<EffortSession> _sessions() => [
  _session(_day(11, 20)),
  _session(_day(11, 25)),
  _session(_day(11, 30)),
  _session(_day(12, 5)),
];

List<DailyValue> _daily() => [
  for (var i = 0; i < 28; i++)
    (date: _day(11, 9).addDays(i), value: 80.0 - 0.05 * i),
];

WeightSummary _weightSummary({int extraDays = 0, List<DailyValue>? days}) {
  final later = [
    for (var i = 1; i <= extraDays; i++)
      (date: _day(12, 6).addDays(i), value: 70.0),
  ];
  return WeightSummary(
    last: WeighIn(
      id: 1,
      at: DateTime.utc(2026, 12, 6, 7),
      offsetMinutes: 0,
      kilograms: 78,
      source: WeighInSource.manual,
    ),
    daily: [...(days ?? _daily()), ...later],
    line: [
      (date: _day(12, 5), value: 78.1),
      (date: _day(12, 6), value: 78.0),
      ...later,
    ],
    rate: const WeightRateBuilding(daysMissing: 1, spanMissing: 1),
    noise: 0.5,
  );
}

ReadinessTrend _readiness(LocalDate today, LocalDate monday) {
  final firstClosed = monday.addDays(-7);
  return ReadinessTrend(
    today: today,
    values: [
      for (var age = 13; age >= 0; age--)
        _readinessOn(today.addDays(-age), firstClosed),
    ],
  );
}

int _readinessOn(LocalDate date, LocalDate firstClosed) {
  final index = date.daysSince(firstClosed);
  if (index < 0 || index > 6) return _otherDayReadiness;
  return _closedReadiness[index];
}

GoalDraft _draft({
  GoalKind kind = GoalKind.loseFat,
  LocalDate startedOn = const LocalDate(2026, 11, 16),
  List<Lever> levers = const [_strength, _sleep, _steps],
}) => GoalDraft(
  kind: kind,
  pace: kind == GoalKind.loseFat ? GoalPace.standard : null,
  startedOn: startedOn,
  anchorKg: kind == GoalKind.loseFat ? 78 : null,
  referenceKg: kind == GoalKind.loseFat ? 70 : null,
  levers: levers,
);

final class _UnreadableStore implements GoalStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('the store was read: ${invocation.memberName}');
}

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

final class _Setup {
  new(this.container, this.store);

  final ProviderContainer container;
  final InMemoryGoalStore store;

  GoalReviewer get reviewer => container.read(goalReviewerProvider.notifier);

  int get revision => container.read(dataRevisionProvider);

  Future<List<GoalWeek>> weeks() => store.weeks(1);
}

Future<_Setup> _setup({
  DateTime? now,
  Set<ModuleId> modules = _both,
  GoalDraft? draft,
  InMemoryGoalStore? store,
  GoalStore? readStore,
  Override? stepsOverride,
  Override? nightsOverride,
  Override? weightOverride,
  int extraWeighIns = 0,
}) async {
  final clock = now ?? _at(12, 7);
  final today = LocalDate(clock.year, clock.month, clock.day);
  final monday = mondayOf(today);
  final memory = store ?? InMemoryGoalStore();
  if (draft != null) await memory.start(draft);
  final container = ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(() => clock),
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      goalStoreProvider.overrideWithValue(readStore ?? memory),
      userProfileStoreProvider.overrideWithValue(
        InMemoryUserProfileStore(const UserProfile(heightCentimeters: 178)),
      ),
      stepsOverride ??
          activityDaysProvider.overrideWith((ref) async => _stepDays()),
      nightsOverride ??
          sleepNightsProvider.overrideWith((ref) async => _nights()),
      effortSessionsProvider.overrideWith((ref) async => _sessions()),
      dailyIntensityProvider.overrideWith((ref) async => <DailyValue>[]),
      readinessTrendProvider.overrideWith(
        (ref) async => _readiness(today, monday),
      ),
      weightOverride ??
          weightSummaryProvider.overrideWith(
            (ref) async => _weightSummary(extraDays: extraWeighIns),
          ),
    ],
  );
  await container.read(enabledModulesProvider.future);
  return _Setup(container, memory);
}

Future<_Setup> _ready({
  DateTime? now,
  Set<ModuleId> modules = _both,
  int extraWeighIns = 0,
}) => _setup(
  now: now,
  modules: modules,
  draft: _draft(),
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

Future<_Setup> _pausableSetup() async {
  final setup = await _ready();
  final previous = _pendingInputs(
    energy: CheckInEnergy.low,
    energyPrevious: CheckInEnergy.normal,
  );
  final current = _pendingInputs(energyPrevious: CheckInEnergy.low);
  await setup.store.addWeek(
    1,
    monday: _day(11, 30),
    inputs: previous,
    review: reviewWeek(previous),
  );
  await setup.store.addWeek(
    1,
    monday: _day(12, 7),
    inputs: current,
    review: reviewWeek(current),
  );
  return setup;
}

GoalWeekData _data() => GoalWeekData(
  steps: {for (final day in _stepDays().values) day.date: day.steps},
  nights: _nights(),
  strengthDays: effortStrengthDays(_sessions()),
);

Lever _starting(GoalKind kind, LocalDate end) =>
    startingLever(kind, leverBaseline(_data(), end: end))!;

Override _weightOf(List<DailyValue> days) => weightSummaryProvider.overrideWith(
  (ref) async => _weightSummary(days: days),
);

Override _noWeight() => weightSummaryProvider.overrideWith((ref) async => null);

Override _throwingWeight() => weightSummaryProvider.overrideWith(
  (ref) async => throw StateError('the weight was read'),
);

Override _nightsOf(Iterable<LocalDate> dates, {required int wake}) =>
    sleepNightsProvider.overrideWith(
      (ref) async => {
        for (final date in dates)
          date: _night(date, onset: _bedAt2330, wake: wake),
      },
    );

Future<_Setup> _withoutLevers({
  GoalKind kind = GoalKind.loseFat,
  DateTime? now,
  Set<ModuleId> modules = _both,
  Override? stepsOverride,
  Override? nightsOverride,
  Override? weightOverride,
}) => _setup(
  now: now,
  modules: modules,
  draft: _draft(kind: kind, levers: const []),
  stepsOverride: stepsOverride,
  nightsOverride: nightsOverride,
  weightOverride: weightOverride,
);

Future<_Setup> _pausedUntil(
  LocalDate? until, {
  GoalKind kind = GoalKind.getFitter,
  DateTime? now,
  int extraWeighIns = 0,
}) async {
  final setup = await _setup(
    now: now,
    draft: _draft(kind: kind),
    extraWeighIns: extraWeighIns,
  );
  await setup.store.setPhase(
    1,
    GoalPhase.paused,
    since: _day(12, 7),
    until: until,
  );
  return setup;
}

void main() {
  group('G5b2b1 case 7: a block start for lose fat with no levers', () {
    final asOf = weightSnapshot(daily: _daily(), asOf: _day(12, 7));

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
      expect(goal.blockStartedOn, _day(12, 7));
      expect(goal.phaseSince, _day(12, 7));
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
      expectSameLevers(levers, [_starting(GoalKind.loseFat, _day(12, 6))]);
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
    Future<void> expectNothingStarted(_Setup setup, Goal before) async {
      expect(await setup.reviewer.startDueBlock(), isFalse);
      expectSameGoal(await setup.store.active(), before);
      expect(setup.revision, 0);
    }

    test('five weigh-in days are not a ready rate', () async {
      final setup = await _withoutLevers(
        weightOverride: _weightOf(_daily().skip(23).toList()),
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
      final setup = await _setup(
        modules: const {},
        readStore: _UnreadableStore(),
      );

      expect(await setup.reviewer.startDueBlock(), isFalse);
      expect(setup.revision, 0);
    });

    test('no goal gives false and no bump', () async {
      final setup = await _setup();

      expect(await setup.reviewer.startDueBlock(), isFalse);
      expect(await setup.store.count(), 0);
      expect(setup.revision, 0);
    });
  });

  group('G5b2b1 case 9: get fitter with no levers', () {
    Future<_Setup> started() async {
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
      expect(goal.blockStartedOn, _day(12, 7));
      expect(goal.blockAnchorKg, isNull);
    });

    test('stores the starting lever of the fixture data', () async {
      final setup = await started();

      expectSameLevers((await setup.store.active())!.levers, [
        _starting(GoalKind.getFitter, _day(12, 6)),
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
          for (var d = 0; d < 7; d++) _day(11, 30).addDays(d),
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
      final setup = await _pausedUntil(_day(12, 20), now: _at(12, 20));
      final before = (await setup.store.active())!;

      final started = await setup.reviewer.startDueBlock();

      expect(started, isFalse);
      expectSameGoal(await setup.store.active(), before);
      expect(setup.revision, 0);
    });

    test('the next day starts a block with no end', () async {
      final setup = await _pausedUntil(_day(12, 20), now: _at(12, 21));

      final started = await setup.reviewer.startDueBlock();

      final goal = (await setup.store.active())!;
      expect(started, isTrue);
      expect(goal.phase, GoalPhase.block);
      expect(goal.blockStartedOn, _day(12, 21));
      expect(goal.phaseSince, _day(12, 21));
      expect(goal.phaseUntil, isNull);
      expect(goal.blockAnchorKg, isNull);
    });

    test('the next day keeps the levers', () async {
      final setup = await _pausedUntil(_day(12, 20), now: _at(12, 21));

      await setup.reviewer.startDueBlock();

      expectSameLevers((await setup.store.active())!.levers, const [
        _strength,
        _sleep,
        _steps,
      ]);
    });

    test('the next day bumps the data revision once', () async {
      final setup = await _pausedUntil(_day(12, 20), now: _at(12, 21));

      await setup.reviewer.startDueBlock();

      expect(setup.revision, 1);
    });
  });

  group('G5b2b1 case 12: lose fat after a dated pause', () {
    test('13 weigh-in days over 12 are still building', () async {
      final setup = await _pausedUntil(
        _day(12, 20),
        kind: GoalKind.loseFat,
        now: _at(12, 21),
      );
      final before = (await setup.store.active())!;

      final started = await setup.reviewer.startDueBlock();

      final snapshot = weightSnapshot(daily: _daily(), asOf: _day(12, 21));
      expect(snapshot.rate, isA<WeightRateBuilding>());
      expect(started, isFalse);
      expectSameGoal(await setup.store.active(), before);
      expect(setup.revision, 0);
    });

    test('15 more weigh-ins give a ready rate and the block starts', () async {
      final setup = await _pausedUntil(
        _day(12, 20),
        kind: GoalKind.loseFat,
        now: _at(12, 21),
        extraWeighIns: 15,
      );

      final started = await setup.reviewer.startDueBlock();

      final snapshot = weightSnapshot(
        daily: _weightSummary(extraDays: 15).daily,
        asOf: _day(12, 21),
      );
      final goal = (await setup.store.active())!;
      expect(snapshot.rate, isA<WeightRateReady>());
      expect(started, isTrue);
      expect(goal.blockStartedOn, _day(12, 21));
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
      final setup = await _setup(
        draft: _draft(kind: GoalKind.getFitter, levers: const []),
        store: inner,
        readStore: gated,
      );
      final pending = setup.reviewer.startDueBlock();
      await pumpEventQueue();
      expect(gated.reachedStartBlock, isTrue);

      setup.container.dispose();
      gated.gate.complete();

      await expectLater(pending, completes);
      expect((await inner.active())!.blockStartedOn, _day(12, 7));
    });
  });

  group('G5b2b1 case 14: no review while there are no levers', () {
    test('the week is the fourth, which a goal with levers reviews', () {
      expect(goalWeekNumber(start: _day(11, 16), today: _day(12, 7)), 4);
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
    Future<_Setup> pregnant() async {
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
      expect(goal.endedOn, _day(12, 7));
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

      await setup.reviewer.checkIn(_day(12, 7), energy: CheckInEnergy.low);

      final goal = (await setup.store.active())!;
      expect(goal.phase, GoalPhase.paused);
      expect(goal.phaseSince, _day(12, 7));
      expect(goal.phaseUntil, isNull);
    });
  });

  group('case 8: the review of the closed week', () {
    test('writes one row on the Monday', () async {
      final setup = await _ready();

      final review = await setup.reviewer.reviewDueWeek();

      final weeks = await setup.weeks();
      expect(weeks, hasLength(1));
      expect(weeks.single.monday, _day(12, 7));
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
      expect(inputs.readiness, _closedReadiness);
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
      final thursday = await _ready(now: _at(12, 10), extraWeighIns: 4);

      await monday.reviewer.reviewDueWeek();
      await thursday.reviewer.reviewDueWeek();

      expectSameInputs(
        (await thursday.weeks()).single.inputs,
        (await monday.weeks()).single.inputs,
      );
    });

    test('still writes the row on the Monday of that week', () async {
      final thursday = await _ready(now: _at(12, 10), extraWeighIns: 4);

      await thursday.reviewer.reviewDueWeek();

      expect((await thursday.weeks()).single.monday, _day(12, 7));
    });
  });

  group('case 11: a gap in the history', () {
    test(
      'writes the new Monday, not the missed one, with no previous',
      () async {
        final store = InMemoryGoalStore();
        final first = await _setup(draft: _draft(), store: store);
        await first.reviewer.reviewDueWeek();
        final later = await _setup(now: _at(12, 21), store: store);
        final before = later.revision;

        await later.reviewer.reviewDueWeek();

        final weeks = await store.weeks(1);
        expect(
          [for (final week in weeks) week.monday],
          [_day(12, 7), _day(12, 21)],
        );
        expect(weeks.last.inputs.adherencePrevious, isNull);
        expect(later.revision, before + 1);
      },
    );
  });

  group('case 12: nothing to review', () {
    test('Goals off gives null, no read of the store and no bump', () async {
      final setup = await _setup(
        modules: const {},
        readStore: _UnreadableStore(),
      );

      final review = await setup.reviewer.reviewDueWeek();

      expect(review, isNull);
      expect(setup.revision, 0);
    });

    test('no goal gives null, no row and no bump', () async {
      final setup = await _setup();

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
        since: _day(12, 1),
        until: _day(12, 28),
      );

      final review = await setup.reviewer.reviewDueWeek();

      expect(review, isNull);
      expect(await setup.weeks(), isEmpty);
      expect(setup.revision, 0);
    });

    test('a goal started on 12-01 has no review on 12-07', () async {
      final setup = await _setup(draft: _draft(startedOn: _day(12, 1)));

      final review = await setup.reviewer.reviewDueWeek();

      expect(review, isNull);
      expect(await setup.weeks(), isEmpty);
      expect(setup.revision, 0);
    });

    test('the same goal is reviewed on 12-14', () async {
      final setup = await _setup(
        now: _at(12, 14),
        draft: _draft(startedOn: _day(12, 1)),
      );

      final review = await setup.reviewer.reviewDueWeek();

      expect(review, isNotNull);
      expect((await setup.weeks()).single.monday, _day(12, 14));
    });
  });

  group('case 13: a source that fails', () {
    test('activity days that throw make the call throw and write '
        'nothing', () async {
      final setup = await _setup(
        draft: _draft(),
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
      final setup = await _setup(
        draft: _draft(kind: GoalKind.sleepBetter, levers: const [_sleep]),
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
        _day(12, 7),
        energy: CheckInEnergy.low,
      );

      expect(review?.rule, ReviewRule.pauseCheckIn);
      expect(review?.action, ReviewAction.pause);
      expect(setup.revision, before + 1);
    });

    test('a refused check-in does not bump', () async {
      final setup = await _pausableSetup();
      await setup.reviewer.checkIn(_day(12, 7), energy: CheckInEnergy.low);
      final before = setup.revision;

      final again = await setup.reviewer.checkIn(
        _day(12, 7),
        energy: CheckInEnergy.good,
      );

      expect(again, isNull);
      expect(setup.revision, before);
    });

    test('a check-in with no goal gives null and does not bump', () async {
      final setup = await _setup();

      final review = await setup.reviewer.checkIn(
        _day(12, 7),
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
      expect(view?.week.monday, _day(12, 7));
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
        monday: _day(11, 30),
        inputs: previous,
        review: reviewWeek(previous),
      );
      setup.container.listen(goalReviewProvider, (_, _) {});
      await setup.reviewer.reviewDueWeek();
      final written = await setup.container.read(goalReviewProvider.future);

      await setup.reviewer.checkIn(_day(12, 7), energy: CheckInEnergy.low);

      final amended = await setup.container.read(goalReviewProvider.future);
      expect(written?.review.rule, ReviewRule.build);
      expect(amended?.review.rule, ReviewRule.pauseCheckIn);
      expect(amended?.week.inputs.energy, CheckInEnergy.low);
    });

    test('is null with Goals off', () async {
      final setup = await _setup(modules: const {});
      setup.container.listen(goalReviewProvider, (_, _) {});

      expect(await setup.container.read(goalReviewProvider.future), isNull);
    });

    test('is null with Goals off over a stored week', () async {
      final written = await _ready();
      await written.reviewer.reviewDueWeek();
      final setup = await _setup(modules: const {}, store: written.store);
      setup.container.listen(goalReviewProvider, (_, _) {});

      expect(await written.weeks(), hasLength(1));
      expect(await setup.container.read(goalReviewProvider.future), isNull);
    });
  });
}
