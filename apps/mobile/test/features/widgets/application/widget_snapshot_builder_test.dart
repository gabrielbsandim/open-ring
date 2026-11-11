import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}) async {
  final container = ProviderContainer.test(overrides: scenario.overrides());
  return buildWidgetSnapshot(
    await container.read(todayViewProvider.future),
    lastWorkout: lastWorkout,
  );
}

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
}
