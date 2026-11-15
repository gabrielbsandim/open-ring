import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/workout_fakes.dart';

const otherApp = 'com.example.other';

final class _Imported implements ImportedWorkoutReader {
  new(this.workouts);

  final List<ImportedWorkout> workouts;

  @override
  Future<ImportedWorkouts> recent({required int limit}) async =>
      (priority: [ringSource, otherApp], workouts: workouts);

  @override
  Future<ImportedWorkout?> byRecordId(String recordId) async => null;
}

SavedWorkout run(int id, DateTime start, {required int bpm}) {
  const elapsed = Duration(minutes: 30);
  return SavedWorkout(
    id: id,
    utcOffset: Duration.zero,
    workout: FinishedWorkout(
      type: WorkoutType.treadmill,
      start: start,
      end: start.add(elapsed),
      elapsed: elapsed,
      heartRate: [
        for (var s = 0; s <= elapsed.inSeconds; s += 5)
          (at: start.add(Duration(seconds: s)), bpm: bpm),
      ],
      route: WorkoutRoute(segments: const []),
      pauses: const [],
      activeKilocalories: 300,
      averageHeartRate: bpm,
      maxHeartRate: bpm,
    ),
  );
}

ImportedWorkout imported(String id, WorkoutType type, DateTime start) =>
    ImportedWorkout(
      recordId: id,
      source: otherApp,
      type: type,
      start: start,
      end: start.add(const Duration(minutes: 45)),
      utcOffset: Duration.zero,
    );

void main() {
  test('daily stress reads the baseline window and groups by day', () async {
    final container = ProviderContainer.test(
      overrides: [
        clockProvider.overrideWithValue(() => metricsNow),
        heartHistoryReaderProvider.overrideWithValue(
          FakeHeartHistoryReader(
            stressReadings: [
              for (var i = 0; i < 4; i++)
                (at: DateTime.utc(2026, 11, 9, 10 + i), level: 30 + 10 * i),
              (at: DateTime.utc(2026, 11, 10, 8), level: 90),
            ],
          ),
        ),
      ],
    );

    final stress = await container.read(dailyStressProvider.future);

    expect(stress, [(date: metricsToday.addDays(-1), value: 45.0)]);
  });

  test('daily intensity joins walking, own and imported workouts', () async {
    final yesterday = DateTime.utc(2026, 11, 9, 18);
    final container = ProviderContainer.test(
      overrides: [
        clockProvider.overrideWithValue(() => metricsNow),
        savedWorkoutZonesProvider.overrideWithValue(
          HeartRateZones(maxHeartRate: 200),
        ),
        activityHistoryReaderProvider.overrideWithValue(
          FakeActivityHistoryReader(
            const [],
            slots: [
              ActivitySlot(
                start: DateTime.utc(2026, 11, 10, 7),
                utcOffset: Duration.zero,
                duration: const Duration(minutes: 15),
                steps: 1700,
                activeKilocalories: 0,
                distanceMeters: 0,
              ),
              ActivitySlot(
                start: yesterday,
                utcOffset: Duration.zero,
                duration: const Duration(minutes: 15),
                steps: 2000,
                activeKilocalories: 0,
                distanceMeters: 0,
              ),
            ],
          ),
        ),
        workoutHistoryReaderProvider.overrideWithValue(
          MemoryWorkoutHistory(
            seed: [
              run(1, yesterday, bpm: 170),
              run(2, DateTime.utc(2026, 7, 1, 18), bpm: 170),
            ],
          ),
        ),
        importedWorkoutReaderProvider.overrideWithValue(
          _Imported([
            imported('a', WorkoutType.strength, yesterday),
            imported('b', WorkoutType.strength, DateTime.utc(2026, 11, 8, 18)),
            imported('c', WorkoutType.yoga, DateTime.utc(2026, 11, 7, 18)),
          ]),
        ),
      ],
    );

    final intensity = await container.read(dailyIntensityProvider.future);

    expect(intensity, hasLength(4));
    expect(intensity[0], (date: metricsToday.addDays(-3), value: 0.0));
    expect(intensity[1], (date: metricsToday.addDays(-2), value: 45.0));
    expect(intensity[2].date, metricsToday.addDays(-1));
    expect(intensity[2].value, closeTo(60, 1e-9));
    expect(intensity[3], (date: metricsToday, value: 15.0));
  });

  test('the history scores today from the readers', () async {
    final scenario = fullDataScenario;
    final container = ProviderContainer.test(overrides: scenario.overrides());

    final history = await container.read(dayScoreHistoryProvider.future);
    final today = history.scoredOn(metricsToday)!;

    expect(history.today, metricsToday);
    expect(history.dates, hasLength(dayScoreHistoryDays));
    expect(today.coverage, 70);
    expect(today.missing, [DayScoreFactor.intensity, DayScoreFactor.stress]);
  });
}
