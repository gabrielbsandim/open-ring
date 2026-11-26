import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_view.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/widgets/application/widget_snapshot_builder.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/metrics_fakes.dart';

Future<WidgetSnapshot> snapshotFor(
  MetricsScenario scenario, {
  WorkoutEntry? lastWorkout,
  Set<ModuleId> enabledModules = const {},
  bool hideNumbers = false,
  DayScoreHistory? dayScoreHistory,
  WeightSummary? weightSummary,
  EnergyNow? energyNow,
  EffortWeek? effortWeek,
  GoalWeekView? goalWeek,
  DateTime? now,
}) async {
  final container = ProviderContainer.test(overrides: scenario.overrides());
  return buildWidgetSnapshot(
    await container.read(todayViewProvider.future),
    lastWorkout: lastWorkout,
    enabledModules: enabledModules,
    hideNumbers: hideNumbers,
    dayScoreHistory: dayScoreHistory,
    weightSummary: weightSummary,
    energyNow: energyNow,
    effortWeek: effortWeek,
    goalWeek: goalWeek,
    now: now,
  );
}

DayScoreInputs _fullInputs({int sleep = 80, int steps = 10000}) {
  const dev = BaselineDeviation(today: 50, baseline: 50, zScore: 0);
  return DayScoreInputs(
    sleepScore: sleep,
    steps: steps,
    stepGoal: 10000,
    intensityMinutes: 150,
    hrv: dev,
    restingHeartRate: dev,
    stress: dev,
    spo2Mean: 97,
    readiness: 80,
  );
}

WeightSummary _weightSummary(WeightRate rate, {double trend = 77.6}) =>
    WeightSummary(
      last: WeighIn(
        id: 1,
        at: metricsNow,
        offsetMinutes: 0,
        kilograms: trend,
        source: WeighInSource.manual,
      ),
      daily: [(date: metricsToday, value: trend)],
      line: [(date: metricsToday, value: trend)],
      rate: rate,
      noise: 0.5,
    );

Goal _goal({
  GoalKind kind = GoalKind.loseFat,
  GoalPhase phase = GoalPhase.block,
  List<Lever> levers = const [
    Lever(kind: LeverKind.strengthDays, target: 2),
    Lever(kind: LeverKind.steps, target: 10000),
  ],
}) => Goal(
  id: 1,
  kind: kind,
  pace: kind == GoalKind.loseFat ? GoalPace.standard : null,
  startedOn: const LocalDate(2026, 11, 2),
  anchorKg: 79,
  referenceKg: null,
  blockStartedOn: const LocalDate(2026, 11, 2),
  blockAnchorKg: 79,
  phase: phase,
  phaseSince: const LocalDate(2026, 11, 2),
  phaseUntil: phase == GoalPhase.paused ? const LocalDate(2026, 11, 16) : null,
  levers: levers,
  endedOn: null,
  endReason: null,
);

final lastWalk = WorkoutListItem(
  id: 3,
  type: WorkoutType.walking,
  start: DateTime.utc(2026, 11, 9, 18),
  end: DateTime.utc(2026, 11, 9, 18, 32),
  utcOffset: const Duration(hours: -3),
  elapsed: const Duration(minutes: 32),
);

void main() {
  test('a recent sync with full data fills every metric', () async {
    final snapshot = await snapshotFor(fullDataScenario);

    expect(snapshot.freshness, SyncFreshness.fresh);
    expect(snapshot.paired, isTrue);
    expect(snapshot.hasHealthData, isTrue);
    expect(snapshot.date, metricsToday);
    expect(snapshot.syncedAt, freshRing.lastSyncAt);
    expect(snapshot.readiness, inInclusiveRange(0, 100));
    expect(snapshot.restingHeartRate, isNotNull);
    expect(snapshot.hrv, 46);
    expect(snapshot.baselineNights, 27);
    expect(snapshot.sleepMinutes, 412);
    expect(snapshot.sleepScore, isNotNull);
    expect(snapshot.steps, 2224);
    expect(snapshot.stepGoal, 8000);
    expect(snapshot.heartRateMean, isNotNull);
    expect(
      snapshot.heartRateMin! <= snapshot.heartRateMean! &&
          snapshot.heartRateMean! <= snapshot.heartRateMax!,
      isTrue,
    );
    expect(snapshot.spo2, isNotNull);
    expect(snapshot.stress, isNotNull);
    expect(snapshot.batteryPercent, 68);
    expect(snapshot.batteryCharging, isTrue);
  });

  test('a sync older than 3 hours is stale but keeps its numbers', () async {
    final snapshot = await snapshotFor(offlineScenario);

    expect(snapshot.freshness, SyncFreshness.stale);
    expect(snapshot.hasHealthData, isTrue);
    expect(snapshot.steps, 2224);
    expect(snapshot.batteryPercent, 14);
    expect(
      snapshot.toJson()['syncedAtMs'],
      metricsNow.subtract(const Duration(hours: 9)).millisecondsSinceEpoch,
    );
    expect(snapshot.toJson()['staleAfterMs'], staleSyncAfter.inMilliseconds);
  });

  test('without a ring or data every value is empty', () async {
    final snapshot = await snapshotFor(noDataScenario);

    expect(snapshot.freshness, SyncFreshness.unpaired);
    expect(snapshot.paired, isFalse);
    expect(snapshot.hasHealthData, isFalse);
    expect(snapshot.syncedAt, isNull);
    expect(snapshot.batteryPercent, isNull);
    final json = snapshot.toJson();
    for (final key in ['readiness', 'sleepMinutes', 'steps', 'heartRateMean']) {
      expect(json[key], isNull, reason: key);
    }
    expect(json['paired'], isFalse);
  });

  test('a paired ring that never synced has no health data', () async {
    final snapshot = await snapshotFor(
      const MetricsScenario(
        nights: 0,
        activityDays: 0,
        ring: RingStatus(paired: true, name: 'R09_C0FE'),
      ),
    );

    expect(snapshot.freshness, SyncFreshness.neverSynced);
    expect(snapshot.paired, isTrue);
    expect(snapshot.hasHealthData, isFalse);
  });

  test(
    'while the baseline builds readiness is empty and the rest is kept',
    () async {
      final snapshot = await snapshotFor(buildingScenario);

      expect(snapshot.freshness, SyncFreshness.fresh);
      expect(snapshot.readiness, isNull);
      expect(snapshot.baselineNights, isNull);
      expect(snapshot.sleepMinutes, 412);
      expect(snapshot.steps, 2224);
      expect(snapshot.heartRateMean, isNotNull);
      expect(snapshot.hasHealthData, isTrue);
    },
  );

  test('the json carries the date and every value the widgets read', () async {
    final json = (await snapshotFor(fullDataScenario)).toJson();

    expect(json['version'], WidgetSnapshot.version);
    expect(json['date'], '2026-11-10');
    expect(json['paired'], isTrue);
    expect(json.keys, containsAll(['stepGoal', 'spo2', 'stress', 'hrv']));
  });

  test('the last workout goes into the json for the workout widget', () async {
    final run = WorkoutListItem(
      id: 4,
      type: WorkoutType.running,
      start: DateTime.utc(2026, 11, 10, 6),
      end: DateTime.utc(2026, 11, 10, 6, 30),
      utcOffset: Duration.zero,
      elapsed: const Duration(minutes: 28, seconds: 5),
      distanceMeters: 5210.4,
    );

    final walk = (await snapshotFor(
      fullDataScenario,
      lastWorkout: lastWalk,
    )).toJson();
    final ran = (await snapshotFor(
      fullDataScenario,
      lastWorkout: run,
    )).toJson();

    expect(walk['lastWorkout'], {
      'type': 'walking',
      'startMs': DateTime.utc(2026, 11, 9, 18).millisecondsSinceEpoch,
      'elapsedSeconds': 1920,
      'distanceMeters': null,
    });
    expect(ran['lastWorkout'], {
      'type': 'running',
      'startMs': DateTime.utc(2026, 11, 10, 6).millisecondsSinceEpoch,
      'elapsedSeconds': 1685,
      'distanceMeters': 5210.4,
    });
  });

  test('a workout from another app sends type and time, no distance', () async {
    final swim = ImportedWorkout(
      recordId: 'w1',
      source: 'com.garmin.android.apps.connectmobile',
      type: WorkoutType.other,
      start: DateTime.utc(2026, 11, 10, 7),
      end: DateTime.utc(2026, 11, 10, 7, 45),
      utcOffset: Duration.zero,
    );

    final json = (await snapshotFor(
      fullDataScenario,
      lastWorkout: swim,
    )).toJson();

    expect(json['lastWorkout'], {
      'type': 'other',
      'startMs': DateTime.utc(2026, 11, 10, 7).millisecondsSinceEpoch,
      'elapsedSeconds': 2700,
      'distanceMeters': null,
    });
  });

  test('without a saved workout the json has no last workout', () async {
    final json = (await snapshotFor(fullDataScenario)).toJson();

    expect(json.containsKey('lastWorkout'), isTrue);
    expect(json['lastWorkout'], isNull);
  });

  group('v2 module fields', () {
    test('disabled modules leave all module fields null', () async {
      final snap = await snapshotFor(
        fullDataScenario,
        dayScoreHistory: DayScoreHistory(
          today: metricsToday,
          days: {metricsToday: _fullInputs()},
        ),
        weightSummary: _weightSummary(
          const WeightRateReady(perWeek: -0.3, low: -0.5, high: -0.1),
        ),
        energyNow: (
          day: const EnergyDayEstimate(
            resting: 1600,
            base: 1400,
            steps: 300,
            workouts: 200,
          ),
          asOf: metricsNow,
        ),
        effortWeek: const EffortWeek(
          monday: LocalDate(2026, 11, 9),
          points: 140,
          strengthDays: 1,
        ),
        goalWeek: GoalWeekRunning(
          goal: _goal(),
          monday: const LocalDate(2026, 11, 9),
          week: 2,
          levers: const [],
          review: null,
        ),
      );

      final json = snap.toJson();
      expect(WidgetSnapshot.version, 2);
      expect(json['version'], 2);
      expect(json['enabledModules'], isEmpty);
      expect(json['hideNumbers'], isFalse);
      expect(snap.dayScore, isNull);
      expect(snap.weight, isNull);
      expect(snap.energy, isNull);
      expect(snap.effort, isNull);
      expect(snap.goals, isNull);
    });

    test('dayScore covers full, partial, afterMidnight, firstDays, noScore, and stale', () async {
      final fullSnap = await snapshotFor(
        fullDataScenario,
        enabledModules: {ModuleId.openScore},
        dayScoreHistory: DayScoreHistory(
          today: metricsToday,
          days: {metricsToday: _fullInputs()},
        ),
        now: metricsNow,
      );
      expect(fullSnap.dayScore?.kind, WidgetDayScoreKind.full);
      expect(fullSnap.dayScore?.coverage, 100);
      expect(fullSnap.dayScore?.pillarPoints, hasLength(5));
      expect(fullSnap.dayScore?.pillarPoints?.every((p) => p != null), isTrue);
      expect(fullSnap.dayScore?.asOf, metricsNow);

      final partialSnap = await snapshotFor(
        fullDataScenario,
        enabledModules: {ModuleId.openScore},
        dayScoreHistory: DayScoreHistory(
          today: metricsToday,
          days: const {
            metricsToday: DayScoreInputs(
              sleepScore: 80,
              steps: 9000,
              stepGoal: 10000,
              intensityMinutes: 150,
              stress: BaselineDeviation(today: 30, baseline: 30, zScore: 0),
            ),
          },
        ),
      );
      expect(partialSnap.dayScore?.kind, WidgetDayScoreKind.partial);
      expect(partialSnap.dayScore?.coverage, 75);
      expect(partialSnap.dayScore?.pillarPoints?[2], isNull);
      expect(partialSnap.dayScore?.pillarPoints?[4], isNull);

      final yesterday = metricsToday.addDays(-1);
      final midnightSnap = await snapshotFor(
        fullDataScenario,
        enabledModules: {ModuleId.openScore},
        dayScoreHistory: DayScoreHistory(
          today: metricsToday,
          days: {
            yesterday: _fullInputs(),
            metricsToday: const DayScoreInputs(
              sleepScore: null,
              steps: null,
              stepGoal: 10000,
            ),
          },
        ),
      );
      expect(midnightSnap.dayScore?.kind, WidgetDayScoreKind.afterMidnight);
      expect(midnightSnap.dayScore?.score, isNotNull);

      final firstDaysSnap = await snapshotFor(
        fullDataScenario,
        enabledModules: {ModuleId.openScore},
        dayScoreHistory: DayScoreHistory(
          today: metricsToday,
          days: const {
            metricsToday: DayScoreInputs(
              sleepScore: 70,
              steps: 5000,
              stepGoal: 10000,
            ),
          },
        ),
      );
      expect(firstDaysSnap.dayScore?.kind, WidgetDayScoreKind.firstDays);
      expect(firstDaysSnap.dayScore?.coverage, 45);

      final older = metricsToday.addDays(-3);
      final noScoreSnap = await snapshotFor(
        fullDataScenario,
        enabledModules: {ModuleId.openScore},
        dayScoreHistory: DayScoreHistory(
          today: metricsToday,
          days: {
            older: _fullInputs(),
            metricsToday: const DayScoreInputs(
              sleepScore: null,
              steps: 500,
              stepGoal: 10000,
            ),
          },
        ),
      );
      expect(noScoreSnap.dayScore?.kind, WidgetDayScoreKind.noScore);
      expect(noScoreSnap.dayScore?.gap, DayScoreGap.night);

      final staleSnap = await snapshotFor(
        offlineScenario,
        enabledModules: {ModuleId.openScore},
        dayScoreHistory: DayScoreHistory(
          today: metricsToday,
          days: {metricsToday: _fullInputs()},
        ),
        now: metricsNow,
      );
      expect(staleSnap.dayScore?.asOf, offlineScenario.ring.lastSyncAt);
    });

    test(
      'weight maps directions and strips trendKilograms when hidden',
      () async {
        final falling = await snapshotFor(
          fullDataScenario,
          enabledModules: {ModuleId.body},
          weightSummary: _weightSummary(
            const WeightRateReady(perWeek: -0.3, low: -0.4, high: -0.2),
          ),
        );
        expect(falling.weight?.direction, WidgetWeightDirection.falling);
        expect(falling.weight?.trendKilograms, 77.6);
        expect(falling.toJson()['weight'], {
          'trendKilograms': 77.6,
          'direction': 'falling',
        });

        final rising = await snapshotFor(
          fullDataScenario,
          enabledModules: {ModuleId.body},
          weightSummary: _weightSummary(
            const WeightRateReady(perWeek: 0.3, low: 0.1, high: 0.5),
          ),
        );
        expect(rising.weight?.direction, WidgetWeightDirection.rising);

        final steady = await snapshotFor(
          fullDataScenario,
          enabledModules: {ModuleId.body},
          weightSummary: _weightSummary(
            const WeightRateReady(perWeek: 0.05, low: -0.1, high: 0.2),
          ),
        );
        expect(steady.weight?.direction, WidgetWeightDirection.steady);

        final building = await snapshotFor(
          fullDataScenario,
          enabledModules: {ModuleId.body},
          weightSummary: _weightSummary(
            const WeightRateBuilding(daysMissing: 2, spanMissing: 4),
          ),
        );
        expect(building.weight?.direction, WidgetWeightDirection.building);

        final hidden = await snapshotFor(
          fullDataScenario,
          enabledModules: {ModuleId.body},
          hideNumbers: true,
          weightSummary: _weightSummary(
            const WeightRateReady(perWeek: -0.3, low: -0.4, high: -0.2),
          ),
        );
        expect(hidden.weight?.direction, WidgetWeightDirection.falling);
        expect(hidden.weight?.trendKilograms, isNull);
        expect(hidden.toJson()['weight'], {
          'trendKilograms': null,
          'direction': 'falling',
        });
      },
    );

    test(
      'energy respects floor, missing/underage states, and hideNumbers',
      () async {
        final ready = await snapshotFor(
          fullDataScenario,
          enabledModules: {ModuleId.energy},
          energyNow: (
            day: const EnergyDayEstimate(
              resting: 1600,
              base: 1400,
              steps: 300,
              workouts: 200,
            ),
            asOf: metricsNow,
          ),
        );
        expect(ready.energy?.lowKcal, 1600);
        expect(ready.energy?.highKcal, 2200);
        expect(ready.toJson()['energy'], {'lowKcal': 1600, 'highKcal': 2200});

        final underFloor = await snapshotFor(
          fullDataScenario,
          enabledModules: {ModuleId.energy},
          energyNow: (
            day: const EnergyDayEstimate(
              resting: 1600,
              base: 60,
              steps: 0,
              workouts: 0,
            ),
            asOf: metricsNow,
          ),
        );
        expect(underFloor.energy, isNull);

        final hidden = await snapshotFor(
          fullDataScenario,
          enabledModules: {ModuleId.energy},
          hideNumbers: true,
          energyNow: (
            day: const EnergyDayEstimate(
              resting: 1600,
              base: 1400,
              steps: 300,
              workouts: 200,
            ),
            asOf: metricsNow,
          ),
        );
        expect(hidden.energy, isNull);
        expect(hidden.toJson()['energy'], isNull);
      },
    );

    test('effort and goals serialize states and levers', () async {
      const monday = LocalDate(2026, 11, 9);
      final running = await snapshotFor(
        fullDataScenario,
        enabledModules: {ModuleId.effort, ModuleId.goals},
        effortWeek: const EffortWeek(
          monday: monday,
          points: 140.4,
          strengthDays: 1,
        ),
        goalWeek: GoalWeekRunning(
          goal: _goal(),
          monday: monday,
          week: 4,
          levers: const [
            LeverProgress(
              lever: Lever(kind: LeverKind.strengthDays, target: 2),
              achieved: 1,
              days: null,
            ),
            LeverProgress(
              lever: Lever(kind: LeverKind.steps, target: 10000),
              achieved: 1,
              days: [
                LeverDayMark.met,
                LeverDayMark.open,
                LeverDayMark.ahead,
                LeverDayMark.ahead,
                LeverDayMark.ahead,
                LeverDayMark.ahead,
                LeverDayMark.ahead,
              ],
            ),
          ],
          review: null,
        ),
      );
      expect(running.toJson()['effort'], {
        'points': 140,
        'targetPoints': 150,
        'strengthDays': 1,
        'strengthTarget': 2,
      });
      expect(running.goals?.state, WidgetGoalsState.running);
      expect(running.goals?.sunday, const LocalDate(2026, 11, 15));
      expect(running.goals?.blockWeeks, goalBlockWeeks);
      expect(running.goals?.levers, hasLength(2));
      expect(running.goals?.levers.last.goal, goalDailyFitDays);

      final paused = await snapshotFor(
        fullDataScenario,
        enabledModules: {ModuleId.goals},
        goalWeek: GoalWeekPaused(
          goal: _goal(phase: GoalPhase.paused),
          until: const LocalDate(2026, 11, 16),
          rule: ReviewRule.pauseCheckIn,
          over: false,
        ),
      );
      expect(paused.goals?.state, WidgetGoalsState.paused);
      expect(paused.goals?.levers, isEmpty);

      final off = await snapshotFor(
        fullDataScenario,
        enabledModules: {ModuleId.goals},
        goalWeek: const GoalWeekNoGoal(),
      );
      expect(off.goals, isNull);
    });
  });
}
