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
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_codec.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/domain/review_inputs.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../goal_fixtures.dart';

const _monday = LocalDate(2026, 12, 7);
const LeverDayMark _met = LeverDayMark.met;
const LeverDayMark _missed = LeverDayMark.missed;
const LeverDayMark _open = LeverDayMark.open;
const LeverDayMark _ahead = LeverDayMark.ahead;

const _strength = Lever(kind: LeverKind.strengthDays, target: 2);
const _sleep = Lever(kind: LeverKind.sleepWindow, target: 690);
const _steps = Lever(kind: LeverKind.steps, target: 10000);
const _effort = Lever(kind: LeverKind.effortPoints, target: 165);
const _wake = Lever(kind: LeverKind.wakeTime, target: 405);

LocalDate _dec(int day) => LocalDate(2026, 12, day);

DateTime _now() => DateTime(2026, 12, 10, 19, 30);

DateTime _utc(LocalDate date, int minuteOfDay) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).add(Duration(minutes: minuteOfDay));

SleepNight _night(LocalDate date, {required int onset, int end = 420}) {
  final onsetDate = onset >= 720 ? date.addDays(-1) : date;
  return SleepNight([
    SleepSpan(
      start: _utc(onsetDate, onset),
      end: _utc(date, end),
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

EffortSession _session(LocalDate date, {required bool strength}) => (
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
  strength: strength,
);

Map<LocalDate, DailyActivity> _weekSteps() => {
  for (final (day, steps) in [(7, 10420), (8, 8310), (9, 11050), (10, 8640)])
    _dec(day): _activity(_dec(day), steps),
};

Map<LocalDate, SleepNight> _weekNights() => {
  _dec(7): _night(_dec(7), onset: 23 * 60 + 20),
  _dec(8): _night(_dec(8), onset: 23 * 60 + 10),
  _dec(9): _night(_dec(9), onset: 5),
  _dec(10): _night(_dec(10), onset: 23 * 60 + 25),
};

List<EffortSession> _weekSessions() => [
  _session(_dec(7), strength: true),
  _session(_dec(8), strength: false),
  _session(const LocalDate(2026, 11, 30), strength: true),
  _session(_dec(12), strength: true),
];

List<DailyValue> _weekPoints() => [
  (date: _dec(7), value: 45),
  (date: _dec(9), value: 80),
  (date: _dec(10), value: 15),
  (date: _dec(6), value: 99),
  (date: _dec(8), value: double.nan),
];

GoalDraft _draft(
  List<Lever> levers, {
  GoalKind kind = GoalKind.loseFat,
  LocalDate startedOn = const LocalDate(2026, 11, 16),
}) => GoalDraft(
  kind: kind,
  pace: kind == GoalKind.loseFat ? GoalPace.standard : null,
  startedOn: startedOn,
  anchorKg: kind == GoalKind.loseFat ? 78.4 : null,
  referenceKg: kind == GoalKind.loseFat ? 74 : null,
  levers: levers,
);

final class _ModulesLoading extends EnabledModulesController {
  new();

  @override
  Future<Set<ModuleId>> build() => Completer<Set<ModuleId>>().future;
}

final class _UnreadableStore implements GoalStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('the store was read: ${invocation.memberName}');
}

final class _Setup {
  new(this.container, this.store);

  final ProviderContainer container;
  final InMemoryGoalStore store;

  Future<GoalWeekView> week() => container.read(goalWeekProvider.future);

  Future<GoalWeekRunning> running() => viewOf<GoalWeekRunning>();

  Future<T> viewOf<T extends GoalWeekView>() async {
    final view = await week();
    expect(view, isA<T>());
    return view as T;
  }

  Future<int> goalId() async => (await store.active())!.id;

  Future<void> addWeek(LocalDate monday, ReviewInputs inputs) async {
    final written = await store.addWeek(
      await goalId(),
      monday: monday,
      inputs: inputs,
      review: reviewWeek(inputs),
    );
    expect(written, isTrue);
    bump();
  }

  void bump() => container.read(dataRevisionProvider.notifier).bump();
}

Future<_Setup> _setup({
  Set<ModuleId> modules = goalModules,
  GoalDraft? draft,
  Map<LocalDate, DailyActivity>? steps,
  Map<LocalDate, SleepNight>? nights,
  List<EffortSession>? sessions,
  List<DailyValue>? points,
  GoalStore? readStore,
  Override? stepsOverride,
  Override? nightsOverride,
  Override? sessionsOverride,
  Override? pointsOverride,
  Override? weightOverride,
}) async {
  final store = InMemoryGoalStore();
  if (draft != null) await store.start(draft);
  final container = ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(_now),
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      goalStoreProvider.overrideWithValue(readStore ?? store),
      stepsOverride ??
          activityDaysProvider.overrideWith((ref) async => steps ?? {}),
      nightsOverride ??
          sleepNightsProvider.overrideWith((ref) async => nights ?? {}),
      sessionsOverride ??
          effortSessionsProvider.overrideWith((ref) async => sessions ?? []),
      pointsOverride ??
          dailyIntensityProvider.overrideWith((ref) async => points ?? []),
      weightOverride ?? weightSummaryProvider.overrideWith((ref) async => null),
    ],
  )..listen(goalWeekProvider, (_, _) {});
  await container.read(enabledModulesProvider.future);
  return _Setup(container, store);
}

Future<_Setup> _running(List<Lever> levers) => _setup(
  draft: _draft(levers),
  steps: _weekSteps(),
  nights: _weekNights(),
  sessions: _weekSessions(),
);

final Override _stepsFail = activityDaysProvider.overrideWith(
  (ref) async => throw StateError('source read'),
);
final Override _nightsFail = sleepNightsProvider.overrideWith(
  (ref) async => throw StateError('source read'),
);
final Override _sessionsFail = effortSessionsProvider.overrideWith(
  (ref) async => throw StateError('source read'),
);
final Override _pointsFail = dailyIntensityProvider.overrideWith(
  (ref) async => throw StateError('source read'),
);
final Override _weightFail = weightSummaryProvider.overrideWith(
  (ref) async => throw StateError('weight read'),
);

Future<_Setup> _failing({
  required GoalDraft draft,
  Set<ModuleId> modules = goalModules,
}) => _setup(
  modules: modules,
  draft: draft,
  stepsOverride: _stepsFail,
  nightsOverride: _nightsFail,
  sessionsOverride: _sessionsFail,
  pointsOverride: _pointsFail,
  weightOverride: _weightFail,
);

const List<Lever> _leversF1 = [strengthLever, sleepLever, stepsLever];

List<(LeverKind, int)> _counts(GoalWeekRunning view) => [
  for (final p in view.levers) (p.lever.kind, p.achieved),
];

void main() {
  group('criterion 10: Goals off gives no goal and an off week', () {
    test('the gate is false with an empty module store', () async {
      final s = await _setup(modules: {});

      expect(s.container.read(goalsEnabledProvider), isFalse);
    });

    test('the gate is true when Goals is enabled', () async {
      final s = await _setup();

      expect(s.container.read(goalsEnabledProvider), isTrue);
    });

    test('the gate is false when only other modules are enabled', () async {
      final s = await _setup(modules: {ModuleId.effort, ModuleId.body});

      expect(s.container.read(goalsEnabledProvider), isFalse);
    });

    test('the active goal is null even with a stored goal', () async {
      final s = await _setup(modules: {}, draft: _draft([_steps]));

      expect(await s.container.read(activeGoalProvider.future), isNull);
    });

    test('the week is off even with a stored goal', () async {
      final s = await _setup(modules: {}, draft: _draft([_steps]));

      expect(await s.week(), isA<GoalWeekOff>());
    });

    test('off does not read the goal store', () async {
      final s = await _setup(modules: {}, readStore: _UnreadableStore());

      expect(await s.container.read(activeGoalProvider.future), isNull);
      expect(await s.week(), isA<GoalWeekOff>());
    });

    test('while the modules load the gate is false', () async {
      final container = ProviderContainer.test(
        overrides: [
          clockProvider.overrideWithValue(_now),
          enabledModulesProvider.overrideWith(_ModulesLoading.new),
          goalStoreProvider.overrideWithValue(InMemoryGoalStore()),
        ],
      );

      expect(container.read(goalsEnabledProvider), isFalse);
    });

    test('while the modules load the week is off', () async {
      final store = InMemoryGoalStore();
      await store.start(_draft([_steps]));
      final container = ProviderContainer.test(
        overrides: [
          clockProvider.overrideWithValue(_now),
          enabledModulesProvider.overrideWith(_ModulesLoading.new),
          goalStoreProvider.overrideWithValue(store),
        ],
      );

      expect(await container.read(activeGoalProvider.future), isNull);
      expect(await container.read(goalWeekProvider.future), isA<GoalWeekOff>());
    });
  });

  group('criterion 11: Goals on with an empty store', () {
    test('gives no goal', () async {
      final s = await _setup();

      expect(await s.week(), isA<GoalWeekNoGoal>());
    });

    test('the active goal is null', () async {
      final s = await _setup();

      expect(await s.container.read(activeGoalProvider.future), isNull);
    });
  });

  group('criterion 12: a running block counts the levers from real data', () {
    final levers = [_strength, _sleep, _steps];

    test('the active goal is the stored one', () async {
      final s = await _running(levers);

      final goal = await s.container.read(activeGoalProvider.future);

      expect(goal?.id, (await s.store.active())?.id);
      expect(goal?.kind, GoalKind.loseFat);
    });

    test('reads the Monday of the week of today', () async {
      final s = await _running(levers);

      expect((await s.running()).monday, _monday);
    });

    test('counts the week of the block as 4', () async {
      final s = await _running(levers);

      expect((await s.running()).week, 4);
    });

    test('counts achieved 1, 3 and 2 in the order of the goal', () async {
      final s = await _running(levers);

      expect((await s.running()).levers.length, 3);
      expect(_counts(await s.running()), [
        (LeverKind.strengthDays, 1),
        (LeverKind.sleepWindow, 3),
        (LeverKind.steps, 2),
      ]);
    });

    test('keeps the order of the levers when they are reversed', () async {
      final s = await _running([_steps, _strength]);

      expect(_counts(await s.running()), [
        (LeverKind.steps, 2),
        (LeverKind.strengthDays, 1),
      ]);
    });

    test('hands each lever its target and marks', () async {
      final s = await _running(levers);
      final view = await s.running();

      expect(view.levers[0].lever.target, 2);
      expect(view.levers[0].days, isNull);
      expect(view.levers[1].days, [
        _met,
        _met,
        _missed,
        _met,
        _ahead,
        _ahead,
        _ahead,
      ]);
      expect(view.levers[2].days, [
        _met,
        _missed,
        _met,
        _open,
        _ahead,
        _ahead,
        _ahead,
      ]);
    });

    test('carries the goal into the view', () async {
      final s = await _running(levers);

      expect((await s.running()).goal.id, (await s.store.active())?.id);
    });

    test('a goal started midweek still counts the days before it', () async {
      final s = await _setup(
        draft: _draft([_steps], startedOn: _dec(9)),
        steps: _weekSteps(),
      );
      final view = await s.running();

      expect(view.monday, _monday);
      expect(view.week, 1);
      expect(view.levers.single.achieved, 2);
    });

    test('a day with no synced steps reads missed', () async {
      final s = await _setup(draft: _draft([_steps]));
      final view = await s.running();

      expect(view.levers.single.days, [
        _missed,
        _missed,
        _missed,
        _open,
        _ahead,
        _ahead,
        _ahead,
      ]);
    });
  });

  group('criterion 13: a getFitter goal counts effort points', () {
    test('sums the finite points of the week', () async {
      final s = await _setup(
        draft: _draft([_effort], kind: GoalKind.getFitter),
        points: _weekPoints(),
      );

      expect(_counts(await s.running()), [(LeverKind.effortPoints, 140)]);
    });
  });

  group('criterion 14: only the sources a lever reads are watched', () {
    test('a wake time goal runs with the other sources throwing', () async {
      final s = await _setup(
        draft: _draft([_wake], kind: GoalKind.sleepBetter),
        nights: {
          _dec(7): _night(_dec(7), onset: 1380, end: 6 * 60 + 15),
          _dec(8): _night(_dec(8), onset: 1380, end: 7 * 60 + 16),
        },
        stepsOverride: activityDaysProvider.overrideWith(
          (ref) async => throw StateError('source read'),
        ),
        sessionsOverride: effortSessionsProvider.overrideWith(
          (ref) async => throw StateError('source read'),
        ),
        pointsOverride: dailyIntensityProvider.overrideWith(
          (ref) async => throw StateError('source read'),
        ),
      );
      final view = await s.running();

      expect(_counts(view), [(LeverKind.wakeTime, 1)]);
      expect(view.levers.single.days, [
        _met,
        _missed,
        _missed,
        _open,
        _ahead,
        _ahead,
        _ahead,
      ]);
    });

    test('a source that throws fails a lever that reads it', () async {
      final s = await _setup(
        draft: _draft([_steps]),
        stepsOverride: activityDaysProvider.overrideWith(
          (ref) async => throw StateError('source read'),
        ),
      );

      await expectLater(s.week(), throwsStateError);
    });
  });

  group('criterion 15: a paused goal stays paused', () {
    test('gives the pause and its last day after a revision bump', () async {
      final s = await _running([_steps]);
      await s.running();
      final goal = (await s.store.active())!;

      await s.store.setPhase(
        goal.id,
        GoalPhase.paused,
        since: _monday,
        until: const LocalDate(2027, 1, 3),
      );
      s.bump();
      final view = await s.week();

      expect(view, isA<GoalWeekPaused>());
      expect((view as GoalWeekPaused).until, const LocalDate(2027, 1, 3));
      expect(view.goal.id, goal.id);
    });

    test('is still paused when the last day has passed', () async {
      final s = await _running([_steps]);
      final goal = (await s.store.active())!;

      await s.store.setPhase(
        goal.id,
        GoalPhase.paused,
        since: _monday,
        until: _dec(8),
      );
      s.bump();
      final view = await s.week();

      expect(view, isA<GoalWeekPaused>());
      expect((view as GoalWeekPaused).until, _dec(8));
    });

    test('a pause with no last day gives a null until', () async {
      final s = await _running([_steps]);
      final goal = (await s.store.active())!;

      await s.store.setPhase(goal.id, GoalPhase.paused, since: _monday);
      s.bump();
      final view = await s.week();

      expect(view, isA<GoalWeekPaused>());
      expect((view as GoalWeekPaused).until, isNull);
    });
  });

  group('criterion 16: maintenance counts like a block', () {
    test('keeps the counts of the running block', () async {
      final s = await _running([_strength, _sleep, _steps]);
      final goal = (await s.store.active())!;

      await s.store.setPhase(goal.id, GoalPhase.maintenance, since: _monday);
      s.bump();
      final view = await s.running();

      expect(view.monday, _monday);
      expect(_counts(view), [
        (LeverKind.strengthDays, 1),
        (LeverKind.sleepWindow, 3),
        (LeverKind.steps, 2),
      ]);
    });
  });

  group('criterion 17: an ended goal leaves only after a revision bump', () {
    test('gives no goal once the goal ended and the revision moved', () async {
      final s = await _running([_steps]);
      final goal = (await s.store.active())!;
      await s.running();

      await s.store.end(goal.id, on: _dec(10), reason: GoalEndReason.person);
      s.bump();

      expect(await s.week(), isA<GoalWeekNoGoal>());
    });

    test('keeps the old week while the revision has not moved', () async {
      final s = await _running([_steps]);
      final goal = (await s.store.active())!;
      await s.running();

      await s.store.end(goal.id, on: _dec(10), reason: GoalEndReason.person);

      expect(await s.week(), isA<GoalWeekRunning>());
    });
  });

  group('review focus 5: a rebuild keeps watching the sources', () {
    test('a source that changes after a rebuild reaches the week', () async {
      var steps = _weekSteps();
      final s = await _setup(
        draft: _draft([_steps]),
        stepsOverride: activityDaysProvider.overrideWith((ref) async => steps),
      );
      expect((await s.running()).levers.single.achieved, 2);

      s.bump();
      expect((await s.running()).levers.single.achieved, 2);
      steps = {..._weekSteps(), _dec(10): _activity(_dec(10), 12000)};
      s.container.invalidate(activityDaysProvider);

      expect((await s.running()).levers.single.achieved, 3);
    });
  });

  const bodyOff = {ModuleId.goals};

  group('acceptance 1 to 3: Hold waits for Body, other goals do not', () {
    test(
      '1: lose fat with Body off holds with every source throwing',
      () async {
        final s = await _failing(draft: _draft([_steps]), modules: bodyOff);
        final view = await s.viewOf<GoalWeekHold>();

        expect(view.goal.id, await s.goalId());
      },
    );

    test('2: lose fat with no levers and Body off holds, not Base', () async {
      final s = await _setup(modules: bodyOff, draft: _draft([]));

      expect(await s.week(), isA<GoalWeekHold>());
    });

    test('3: a sleepBetter goal with Body off keeps running', () async {
      final s = await _setup(
        modules: bodyOff,
        draft: _draft([_wake], kind: GoalKind.sleepBetter),
      );
      final view = await s.running();

      expect(view.levers.single.lever.kind, LeverKind.wakeTime);
    });
  });

  group('acceptance 4 to 7: Base reads the weight only for lose fat', () {
    test('4: lose fat with no levers gives the snapshot rate', () async {
      final summary = goalWeightSummary();
      final s = await _setup(
        draft: _draft([]),
        weightOverride: weightSummaryProvider.overrideWith(
          (ref) async => summary,
        ),
      );
      final view = await s.viewOf<GoalWeekBase>();
      final expected = weightSnapshot(daily: summary.daily, asOf: _dec(10));

      expect(view.goal.id, await s.goalId());
      expect(expected.rate, isA<WeightRateReady>());
      expect(summary.rate, isA<WeightRateBuilding>());
      expect(view.rate, isA<WeightRateReady>());
      expect(
        (view.rate! as WeightRateReady).perWeek,
        (expected.rate! as WeightRateReady).perWeek,
      );
    });

    test('4: a short weigh-in history gives a building rate', () async {
      final summary = goalWeightSummary(
        days: [(date: _dec(8), value: 78.0), (date: _dec(9), value: 77.9)],
      );
      final s = await _setup(
        draft: _draft([]),
        weightOverride: weightSummaryProvider.overrideWith(
          (ref) async => summary,
        ),
      );
      final view = await s.viewOf<GoalWeekBase>();
      final expected = weightSnapshot(daily: summary.daily, asOf: _dec(10));

      expect(expected.rate, isA<WeightRateBuilding>());
      expect(view.rate, isA<WeightRateBuilding>());
      expect(
        (view.rate! as WeightRateBuilding).daysMissing,
        (expected.rate! as WeightRateBuilding).daysMissing,
      );
    });

    test('5: a null weight summary gives a null rate', () async {
      final s = await _setup(draft: _draft([]));
      final view = await s.viewOf<GoalWeekBase>();

      expect(view.rate, isNull);
    });

    test('6: a weight that throws fails the week', () async {
      final s = await _setup(draft: _draft([]), weightOverride: _weightFail);

      await expectLater(s.week(), throwsStateError);
    });

    test('7: getFitter with no levers never reads the weight', () async {
      final s = await _setup(
        draft: _draft([], kind: GoalKind.getFitter),
        weightOverride: _weightFail,
      );
      final view = await s.viewOf<GoalWeekBase>();

      expect(view.rate, isNull);
    });

    test(
      'focus 5: sleepBetter with no levers never reads the weight',
      () async {
        final s = await _setup(
          draft: _draft([], kind: GoalKind.sleepBetter),
          weightOverride: _weightFail,
        );
        final view = await s.viewOf<GoalWeekBase>();

        expect(view.rate, isNull);
      },
    );

    test('focus 5: a running lose fat goal never reads the weight', () async {
      final s = await _setup(
        draft: _draft([_steps]),
        steps: _weekSteps(),
        weightOverride: _weightFail,
      );

      expect((await s.running()).levers.single.achieved, 2);
    });

    test('a goal with no levers is Base even with a recovery row', () async {
      final s = await _setup(draft: _draft([]));
      await s.addWeek(_monday, f1Recovering(recoveryPrevious: false));

      expect(await s.week(), isA<GoalWeekBase>());
    });
  });

  group('acceptance 8 to 10: Recovery is this Monday of this block', () {
    test('8: a recovery row of this Monday reads no lever source', () async {
      final s = await _setup(
        draft: _draft([_steps]),
        stepsOverride: _stepsFail,
      );
      await s.addWeek(_monday, f1Recovering(recoveryPrevious: false));
      final view = await s.viewOf<GoalWeekRecovery>();

      expect(view.monday, _monday);
      expect(view.week, 4);
      expect(view.goal.id, await s.goalId());
    });

    test('focus 3: Recovery reads no source at all', () async {
      final s = await _failing(draft: _draft([_steps]));
      await s.addWeek(_monday, f1Recovering(recoveryPrevious: false));
      final view = await s.viewOf<GoalWeekRecovery>();

      expect(view.week, 4);
    });

    test('9: a recovery row of an earlier Monday is a running week', () async {
      final s = await _setup(draft: _draft([_steps]), steps: _weekSteps());
      await s.addWeek(
        const LocalDate(2026, 11, 30),
        f1Recovering(recoveryPrevious: false),
      );
      final view = await s.running();

      expect(view.monday, _monday);
      expect(view.levers.single.achieved, 2);
    });

    test('10: a recovery row of an earlier block is a running week', () async {
      final s = await _setup(draft: _draft([_steps]), steps: _weekSteps());
      await s.addWeek(_monday, f1Recovering(recoveryPrevious: false));
      await s.store.startBlock(await s.goalId(), on: _dec(9), anchorKg: null);
      s.bump();
      final view = await s.running();

      expect(view.week, 1);
      expect(view.levers.single.achieved, 2);
    });

    test('a recovery row dated on the block start is still Recovery', () async {
      final s = await _setup(draft: _draft([_steps], startedOn: _monday));
      await s.addWeek(_monday, f1Recovering(recoveryPrevious: false));
      final view = await s.viewOf<GoalWeekRecovery>();

      expect(view.week, 1);
    });
  });

  group('acceptance 11 to 15: the review of the running week', () {
    test('11: a pending row of this Monday is the review', () async {
      final s = await _setup(draft: _draft(_leversF1));
      await s.addWeek(_monday, f1);
      final view = await s.running();

      expect(view.review?.monday, _monday);
      expect(view.review?.rule, ReviewRule.build);
      expect(view.review?.pending, isTrue);
    });

    test('12: a declined review is gone after the bump', () async {
      final s = await _setup(draft: _draft(_leversF1));
      await s.addWeek(_monday, f1);
      expect((await s.running()).review, isNotNull);

      await s.store.answer(await s.goalId(), _monday, WeekAnswer.declined);
      s.bump();

      expect((await s.running()).review, isNull);
    });

    test('focus 1: a row only write reaches the view with the bump', () async {
      final s = await _setup(draft: _draft(_leversF1));
      await s.addWeek(_monday, f1);
      final before = await s.running();
      expect(before.review, isNotNull);

      await s.store.answer(await s.goalId(), _monday, WeekAnswer.declined);
      s.bump();
      final after = await s.running();

      expect(after.review, isNull);
      expect(
        [for (final p in after.levers) p.lever.target],
        [for (final lever in _leversF1) lever.target],
      );
    });

    test(
      '13: an accepted review is gone and its levers are in force',
      () async {
        final s = await _setup(draft: _draft(_leversF1));
        await s.addWeek(_monday, f1);
        final goal = (await s.store.active())!;
        final change = reviewWeek(f1).change!;
        final expected = applyLeverChange(goal.levers, change);

        await s.store.answer(goal.id, _monday, WeekAnswer.accepted);
        s.bump();
        final view = await s.running();

        expect(view.review, isNull);
        expect(
          [for (final p in view.levers) (p.lever.kind, p.lever.target)],
          [for (final lever in expected) (lever.kind, lever.target)],
        );
        expect([
          for (final lever in expected) lever.target,
        ], isNot([for (final lever in goal.levers) lever.target]));
      },
    );

    test('14: a pending row of an earlier block is not the review', () async {
      final s = await _setup(draft: _draft(_leversF1));
      await s.addWeek(_monday, f1);
      await s.store.startBlock(await s.goalId(), on: _dec(9), anchorKg: null);
      s.bump();
      final view = await s.running();

      expect(view.week, 1);
      expect(view.review, isNull);
    });

    test('15: a row with no proposed change is not the review', () async {
      final s = await _setup(draft: _draft([_steps]));
      expect(reviewWeek(f0).change, isNull);
      await s.addWeek(_monday, f0);
      final view = await s.running();

      expect(view.review, isNull);
    });

    test(
      'focus 2: a pending row of an earlier Monday is not the review',
      () async {
        final s = await _setup(draft: _draft(_leversF1));
        await s.addWeek(const LocalDate(2026, 11, 30), f1);
        final view = await s.running();

        expect(view.monday, _monday);
        expect(view.review, isNull);
      },
    );

    test('a week with no row has no review', () async {
      final s = await _setup(draft: _draft(_leversF1));

      expect((await s.running()).review, isNull);
    });
  });

  group('acceptance 16 to 19: a pause names its rule and its end', () {
    test('16: a pause written by the review names the rule', () async {
      final s = await _setup(draft: _draft([_steps]));
      final inputs = f1Recovering(recoveryPrevious: true);
      await s.addWeek(_monday, inputs);
      final view = await s.viewOf<GoalWeekPaused>();

      expect(reviewWeek(inputs).rule, ReviewRule.recoveryWeek);
      expect(view.rule, ReviewRule.recoveryWeek);
      expect(view.until, _dec(20));
      expect(view.over, isFalse);
    });

    test('17: a pause by the person, past its last day, is over', () async {
      final s = await _setup(draft: _draft([_steps]));
      await s.store.setPhase(
        await s.goalId(),
        GoalPhase.paused,
        since: _monday,
        until: _dec(8),
      );
      s.bump();
      final view = await s.viewOf<GoalWeekPaused>();

      expect(view.rule, isNull);
      expect(view.over, isTrue);
    });

    test('18: a pause on its last day is not over', () async {
      final s = await _setup(draft: _draft([_steps]));
      await s.store.setPhase(
        await s.goalId(),
        GoalPhase.paused,
        since: _monday,
        until: _dec(10),
      );
      s.bump();
      final view = await s.viewOf<GoalWeekPaused>();

      expect(view.until, _dec(10));
      expect(view.over, isFalse);
    });

    test('19: a pause with no last day is never over', () async {
      final s = await _setup(draft: _draft([_steps]));
      await s.store.setPhase(
        await s.goalId(),
        GoalPhase.paused,
        since: _monday,
      );
      s.bump();
      final view = await s.viewOf<GoalWeekPaused>();

      expect(view.until, isNull);
      expect(view.over, isFalse);
    });

    test('a row of another Monday does not name the pause rule', () async {
      final s = await _setup(draft: _draft([_steps]));
      await s.addWeek(
        const LocalDate(2026, 11, 30),
        f1Recovering(recoveryPrevious: true),
      );
      await s.store.setPhase(
        await s.goalId(),
        GoalPhase.paused,
        since: _monday,
        until: _dec(20),
      );
      s.bump();
      final view = await s.viewOf<GoalWeekPaused>();

      expect(view.rule, isNull);
    });

    test('focus 3: a pause reads no source at all', () async {
      final s = await _failing(draft: _draft([_steps]));
      await s.addWeek(_monday, f1Recovering(recoveryPrevious: true));
      final view = await s.viewOf<GoalWeekPaused>();

      expect(view.rule, ReviewRule.recoveryWeek);
    });
  });

  group('acceptance 20 and 21: Hold sits between the two pauses', () {
    test('20: a pause that is not over beats Hold', () async {
      final s = await _setup(modules: bodyOff, draft: _draft([_steps]));
      await s.store.setPhase(
        await s.goalId(),
        GoalPhase.paused,
        since: _monday,
        until: const LocalDate(2027, 1, 3),
      );
      s.bump();
      final view = await s.viewOf<GoalWeekPaused>();

      expect(view.over, isFalse);
    });

    test('21: a pause that is over gives way to Hold', () async {
      final s = await _setup(modules: bodyOff, draft: _draft([_steps]));
      await s.store.setPhase(
        await s.goalId(),
        GoalPhase.paused,
        since: _monday,
        until: _dec(8),
      );
      s.bump();

      expect(await s.week(), isA<GoalWeekHold>());
    });

    test('focus 4: a pause on its last day is not Hold either', () async {
      final s = await _setup(modules: bodyOff, draft: _draft([_steps]));
      await s.store.setPhase(
        await s.goalId(),
        GoalPhase.paused,
        since: _monday,
        until: _dec(10),
      );
      s.bump();
      final view = await s.viewOf<GoalWeekPaused>();

      expect(view.over, isFalse);
    });

    test('a pause with no last day and Body off is a pause', () async {
      final s = await _setup(modules: bodyOff, draft: _draft([_steps]));
      await s.store.setPhase(
        await s.goalId(),
        GoalPhase.paused,
        since: _monday,
      );
      s.bump();

      expect(await s.week(), isA<GoalWeekPaused>());
    });

    test('a paused sleepBetter goal past its last day stays paused', () async {
      final s = await _setup(
        modules: bodyOff,
        draft: _draft([_wake], kind: GoalKind.sleepBetter),
      );
      await s.store.setPhase(
        await s.goalId(),
        GoalPhase.paused,
        since: _monday,
        until: _dec(8),
      );
      s.bump();
      final view = await s.viewOf<GoalWeekPaused>();

      expect(view.over, isTrue);
    });
  });

  group('acceptance 22: Goals off reads nothing', () {
    test('a recovery row with Goals off gives Off and no store read', () async {
      final s = await _setup(
        modules: {},
        draft: _draft([_steps]),
        readStore: _UnreadableStore(),
      );
      await s.addWeek(_monday, f1Recovering(recoveryPrevious: false));

      expect(await s.week(), isA<GoalWeekOff>());
    });
  });
}
