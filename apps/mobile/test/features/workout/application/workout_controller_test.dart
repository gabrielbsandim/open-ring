import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_state.dart';
import 'package:open_ring/features/workout/domain/live_heart_rate_source.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_store.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_store.dart';

import '../../../helpers/database.dart';
import '../../../helpers/workout_fakes.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late StreamController<void> ticks;
  late FakeHeartRateSource heartRate;
  late FakeLocationSource location;

  setUp(() {
    db = memoryDatabase();
    clock = FakeClock(workoutStart);
    ticks = StreamController<void>.broadcast(sync: true);
    heartRate = FakeHeartRateSource();
    location = FakeLocationSource();
  });

  ProviderContainer container({WorkoutStore? store, UserProfile? profile}) {
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock.call),
        workoutTicksProvider.overrideWithValue(() => ticks.stream),
        liveHeartRateSourceProvider.overrideWithValue(heartRate),
        locationSourceProvider.overrideWithValue(location),
        workoutStoreProvider.overrideWithValue(store ?? DriftWorkoutStore(db)),
        userProfileStoreProvider.overrideWithValue(
          InMemoryUserProfileStore(
            profile ?? const UserProfile(birthYear: 1996, weightKilograms: 70),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  var meters = 0.0;

  void second({int? bpm, double? speed}) {
    clock.advance(const Duration(seconds: 1));
    if (speed != null) {
      meters += speed;
      location.emit(
        fixAt(clock.now.difference(workoutStart), northMeters: meters),
      );
    }
    if (bpm != null) heartRate.emit(bpm);
    ticks.add(null);
  }

  setUp(() => meters = 0);

  test('ticks once per second and excludes paused time', () async {
    final c = container();
    final controller = c.read(workoutProvider.notifier);

    await controller.start(WorkoutType.running, notice: testNotice);
    location.emit(fixAt(Duration.zero, northMeters: 0));
    for (var i = 0; i < 10; i++) {
      second(bpm: 150, speed: 3);
    }
    var snapshot = c.read(workoutProvider).snapshot!;
    expect(snapshot.status, WorkoutStatus.running);
    expect(snapshot.elapsed, const Duration(seconds: 10));
    expect(snapshot.distanceMeters, closeTo(30, 1e-6));
    expect(snapshot.currentPace!.inMilliseconds, closeTo(333333, 1));
    expect(snapshot.currentHeartRate, 150);
    expect(snapshot.currentZone, 3);
    expect(snapshot.activeKilocalories, closeTo(8.8 * 70 * 10 / 3600, 1e-9));

    controller.pause();
    for (var i = 0; i < 60; i++) {
      second(bpm: 100, speed: 3);
    }
    snapshot = c.read(workoutProvider).snapshot!;
    expect(snapshot.status, WorkoutStatus.paused);
    expect(snapshot.elapsed, const Duration(seconds: 10));
    expect(snapshot.distanceMeters, closeTo(30, 1e-6));
    expect(snapshot.currentHeartRate, isNull);

    controller.resume();
    for (var i = 0; i < 10; i++) {
      second(bpm: 160, speed: 3);
    }
    snapshot = c.read(workoutProvider).snapshot!;
    expect(snapshot.elapsed, const Duration(seconds: 20));
    expect(snapshot.distanceMeters, closeTo(57, 1e-6));
    expect(snapshot.averageHeartRate, 155);
    expect(snapshot.maxHeartRate, 160);
  });

  test(
    'finish stops every source and persists session, HR and route',
    () async {
      final c = container();
      final controller = c.read(workoutProvider.notifier);
      await controller.start(WorkoutType.running, notice: testNotice);
      location.emit(fixAt(Duration.zero, northMeters: 0));
      for (var i = 0; i < 5; i++) {
        second(bpm: 140, speed: 3);
      }
      controller.pause();
      second();
      second();
      controller.resume();
      for (var i = 0; i < 5; i++) {
        second(bpm: 150, speed: 3);
      }

      await controller.finish();

      final state = c.read(workoutProvider);
      expect(state.status, WorkoutStatus.finished);
      expect(state.save, WorkoutSave.saved);
      expect(heartRate.cancels, 1);
      expect(location.cancels, 1);
      expect(ticks.hasListener, isFalse);

      final workout = await db.select(db.workouts).getSingle();
      expect(state.workoutId, workout.id);
      expect(workout.activityType, 'running');
      expect(workout.startUtcMs, workoutStart.utcMs);
      expect(workout.endUtcMs, clock.now.utcMs);
      expect(workout.elapsedMs, 10000);
      expect(workout.distanceMeters, closeTo(27, 1e-6));
      expect(workout.averageHeartRate, 145);
      expect(await rowCount(db, 'workout_hr_samples'), 10);
      expect(await rowCount(db, 'workout_route_points'), 11);
      final pause = await db.select(db.workoutPauses).getSingle();
      expect(pause.endUtcMs - pause.startUtcMs, 2000);

      final outbox = await HealthOutboxDao(db).all();
      expect(outbox.map((r) => (r.kind, r.fromUtcMs, r.toUtcMs)), [
        (HealthRecordKind.workout, workoutStart.utcMs, clock.now.utcMs),
      ]);
    },
  );

  test('discard stops the sources and writes nothing', () async {
    final c = container();
    final controller = c.read(workoutProvider.notifier);
    await controller.start(WorkoutType.walking, notice: testNotice);
    second(bpm: 120, speed: 1.5);

    await controller.discard();

    expect(c.read(workoutProvider).status, WorkoutStatus.discarded);
    expect(heartRate.listening, isFalse);
    expect(location.listening, isFalse);
    expect(await rowCount(db, 'workouts'), 0);
    expect(await rowCount(db, 'health_outbox'), 0);
  });

  test('an indoor workout never asks for location', () async {
    final c = container();

    await c
        .read(workoutProvider.notifier)
        .start(WorkoutType.other, notice: testNotice);
    second(bpm: 110);

    expect(location.listens, 0);
    expect(heartRate.listens, 1);
    expect(c.read(workoutProvider).snapshot!.distanceMeters, isNull);
  });

  test('a lost ring or a refused location keeps the workout running', () async {
    final c = container();
    await c
        .read(workoutProvider.notifier)
        .start(WorkoutType.running, notice: testNotice);

    heartRate.fail(const HeartRateUnavailable(HeartRateProblem.busy));
    location.fail(const LocationUnavailable(LocationProblem.denied));
    second();

    final state = c.read(workoutProvider);
    expect(state.status, WorkoutStatus.running);
    expect(state.snapshot!.elapsed, const Duration(seconds: 1));
    expect(state.heartRateProblem, HeartRateProblem.busy);
    expect(state.locationProblem, LocationProblem.denied);
    expect(heartRate.listening, isFalse);
    expect(location.listening, isFalse);
  });

  test('a silent ring reads as lost while time and GPS keep going', () async {
    final c = container();
    await c
        .read(workoutProvider.notifier)
        .start(WorkoutType.running, notice: testNotice);
    location.emit(fixAt(Duration.zero, northMeters: 0));
    for (var i = 0; i < 5; i++) {
      second(bpm: 150, speed: 3);
    }
    final silence = heartRateLostAfter.inSeconds;
    for (var i = 0; i < silence - 1; i++) {
      second(speed: 3);
    }
    expect(c.read(workoutProvider).heartRateStalled, isFalse);

    second(speed: 3);
    final state = c.read(workoutProvider);
    expect(state.heartRateStalled, isTrue);
    expect(state.heartRateProblem, isNull);
    expect(state.status, WorkoutStatus.running);
    expect(state.snapshot!.elapsed, Duration(seconds: 5 + silence));
    expect(state.snapshot!.distanceMeters, closeTo(3.0 * (5 + silence), 1e-6));
    expect(state.snapshot!.heartRateSamples, 5);
    expect(heartRate.listening, isTrue);

    second(bpm: 152, speed: 3);
    expect(c.read(workoutProvider).heartRateStalled, isFalse);
  });

  test('out of range readings do not count as heart rate', () async {
    final c = container();
    await c
        .read(workoutProvider.notifier)
        .start(WorkoutType.other, notice: testNotice);
    for (var i = 0; i < heartRateLostAfter.inSeconds; i++) {
      second(bpm: 0);
    }

    expect(c.read(workoutProvider).heartRateStalled, isTrue);
  });

  test('reconnect restarts the ring and leaves the gap empty', () async {
    final store = RecordingWorkoutStore();
    final c = container(store: store);
    final controller = c.read(workoutProvider.notifier);
    await controller.start(WorkoutType.running, notice: testNotice);
    for (var i = 0; i < 5; i++) {
      second(bpm: 140);
    }
    for (var i = 0; i < heartRateLostAfter.inSeconds; i++) {
      second();
    }
    expect(c.read(workoutProvider).heartRateStalled, isTrue);

    await controller.reconnectHeartRate();

    var state = c.read(workoutProvider);
    expect(state.heartRateStalled, isFalse);
    expect(state.heartRateProblem, isNull);
    expect(state.status, WorkoutStatus.running);
    expect(heartRate.cancels, 1);
    expect(heartRate.listens, 2);
    expect(heartRate.listening, isTrue);

    for (var i = 0; i < 5; i++) {
      second(bpm: 150);
    }
    state = c.read(workoutProvider);
    expect(state.snapshot!.currentHeartRate, 150);
    await controller.finish();

    final workout = store.saved.single;
    expect(workout.elapsed, const Duration(seconds: 40));
    expect(workout.heartRate, hasLength(10));
    expect(
      workout.heartRate[5].at.difference(workout.heartRate[4].at),
      const Duration(seconds: 31),
    );
    expect(workout.averageHeartRate, 145);
  });

  test('a reconnected ring that stays silent reads as lost again', () async {
    final c = container();
    final controller = c.read(workoutProvider.notifier);
    await controller.start(WorkoutType.running, notice: testNotice);
    for (var i = 0; i < heartRateLostAfter.inSeconds; i++) {
      second();
    }
    await controller.reconnectHeartRate();
    for (var i = 0; i < heartRateLostAfter.inSeconds - 1; i++) {
      second();
    }
    expect(c.read(workoutProvider).heartRateStalled, isFalse);

    second();
    expect(c.read(workoutProvider).heartRateStalled, isTrue);
  });

  test('reconnect after a ring error clears the problem', () async {
    final c = container();
    final controller = c.read(workoutProvider.notifier);
    await controller.start(WorkoutType.running, notice: testNotice);
    second(bpm: 140);
    heartRate.fail(const HeartRateUnavailable(HeartRateProblem.unreachable));
    second();
    expect(heartRate.listening, isFalse);

    await controller.reconnectHeartRate();
    second(bpm: 141);

    final state = c.read(workoutProvider);
    expect(state.heartRateProblem, isNull);
    expect(state.snapshot!.currentHeartRate, 141);
    expect(heartRate.listens, 2);
  });

  test('a ring stream that ends reads as unreachable', () async {
    final c = container();
    await c
        .read(workoutProvider.notifier)
        .start(WorkoutType.running, notice: testNotice);
    second(bpm: 140);

    heartRate.close();
    await pumpEventQueue();
    second();

    final state = c.read(workoutProvider);
    expect(state.heartRateProblem, HeartRateProblem.unreachable);
    expect(state.status, WorkoutStatus.running);
  });

  test('two reconnect taps open one new link', () async {
    final c = container();
    final controller = c.read(workoutProvider.notifier);
    await controller.start(WorkoutType.running, notice: testNotice);
    heartRate.fail(const HeartRateUnavailable(HeartRateProblem.busy));

    await Future.wait([
      controller.reconnectHeartRate(),
      controller.reconnectHeartRate(),
    ]);

    expect(heartRate.listens, 2);
  });

  test('try again restarts a failed GPS while time and HR go on', () async {
    final c = container();
    final controller = c.read(workoutProvider.notifier);
    await controller.start(WorkoutType.walking, notice: testNotice);
    location.emit(fixAt(Duration.zero, northMeters: 0));
    for (var i = 0; i < 5; i++) {
      second(bpm: 120, speed: 1.5);
    }
    location.fail(StateError('gps crashed'));
    for (var i = 0; i < 5; i++) {
      second(bpm: 120);
    }
    var state = c.read(workoutProvider);
    expect(state.locationProblem, LocationProblem.failed);
    expect(state.snapshot!.elapsed, const Duration(seconds: 10));
    expect(state.snapshot!.heartRateSamples, 10);
    expect(location.listening, isFalse);

    await controller.retryLocation();
    state = c.read(workoutProvider);
    expect(state.locationProblem, isNull);
    expect(location.listens, 2);
    expect(location.notice, same(testNotice));

    for (var i = 0; i < 5; i++) {
      second(bpm: 120, speed: 1.5);
    }
    state = c.read(workoutProvider);
    expect(state.snapshot!.trackPoints, 11);
    expect(state.snapshot!.distanceMeters, closeTo(15, 1e-6));
    expect(state.snapshot!.heartRateSamples, 15);
  });

  test('a location stream that ends reads as a failed GPS', () async {
    final c = container();
    await c
        .read(workoutProvider.notifier)
        .start(WorkoutType.running, notice: testNotice);

    location.close();
    await pumpEventQueue();

    expect(c.read(workoutProvider).locationProblem, LocationProblem.failed);
  });

  test('reconnect and try again need a live workout', () async {
    final c = container();
    final controller = c.read(workoutProvider.notifier);
    await controller.reconnectHeartRate();
    await controller.retryLocation();
    expect(heartRate.listens, 0);
    expect(location.listens, 0);

    await controller.start(WorkoutType.other, notice: testNotice);
    await controller.retryLocation();
    expect(location.listens, 0);

    second(bpm: 120);
    await controller.finish();
    await controller.reconnectHeartRate();
    expect(heartRate.listens, 1);
  });

  test('a failed save can be retried without losing the session', () async {
    final c = container(store: FlakyWorkoutStore(DriftWorkoutStore(db)));
    final controller = c.read(workoutProvider.notifier);
    await controller.start(WorkoutType.running, notice: testNotice);
    second(bpm: 140);

    await controller.finish();
    expect(c.read(workoutProvider).save, WorkoutSave.failed);
    expect(await rowCount(db, 'workouts'), 0);

    await controller.saveAgain();
    expect(c.read(workoutProvider).save, WorkoutSave.saved);
    expect(await rowCount(db, 'workouts'), 1);
    expect(await rowCount(db, 'health_outbox'), 1);
  });

  test('zones use the profile max HR over the age formula', () async {
    final c = container(
      profile: const UserProfile(birthYear: 1996, maxHeartRate: 200),
    );
    await c
        .read(workoutProvider.notifier)
        .start(WorkoutType.running, notice: testNotice);

    second(bpm: 152);

    final snapshot = c.read(workoutProvider).snapshot!;
    expect(snapshot.currentZone, 3);
    expect(snapshot.activeKilocalories, isNull);
  });

  test('start, pause and finish are ignored when they do not apply', () async {
    final c = container();
    final controller = c.read(workoutProvider.notifier)
      ..pause()
      ..resume();
    await controller.finish();
    expect(c.read(workoutProvider).status, WorkoutStatus.idle);

    await controller.start(WorkoutType.running, notice: testNotice);
    await controller.start(WorkoutType.walking, notice: testNotice);
    controller.resume();

    expect(c.read(workoutProvider).snapshot!.type, WorkoutType.running);
    expect(heartRate.listens, 1);
  });

  test('profile zones need an age or a max HR in range', () {
    expect(workoutProfileOf(null, year: 2026).zones, isNull);
    expect(workoutProfileOf(const UserProfile(), year: 2026).zones, isNull);
    expect(
      workoutProfileOf(
        const UserProfile(birthYear: 1996),
        year: 2026,
      ).zones?.maxHeartRate,
      190,
    );
    expect(
      workoutProfileOf(const UserProfile(birthYear: 1900), year: 2026).zones,
      isNull,
    );
  });

  group('heart rate while paused', () {
    test('pause pauses the heart rate and resume resumes it', () async {
      final c = container();
      final controller = c.read(workoutProvider.notifier);
      await controller.start(WorkoutType.running, notice: testNotice);
      second(bpm: 140);

      controller.pause();
      expect(heartRate.paused, isTrue);
      expect(heartRate.pauses, 1);
      expect(heartRate.cancels, 0);

      controller.resume();
      expect(heartRate.paused, isFalse);
      expect(heartRate.resumes, 1);
      expect(heartRate.listens, 1);
    });

    test('a long pause never flags the heart rate as stalled', () async {
      final c = container();
      final controller = c.read(workoutProvider.notifier);
      await controller.start(WorkoutType.running, notice: testNotice);
      second(bpm: 140);

      controller.pause();
      for (var i = 0; i < heartRateLostAfter.inSeconds * 2; i++) {
        second();
      }

      expect(c.read(workoutProvider).heartRateStalled, isFalse);
    });

    test('after resume the stall timer starts at the resume instant', () async {
      final c = container();
      final controller = c.read(workoutProvider.notifier);
      await controller.start(WorkoutType.running, notice: testNotice);
      second(bpm: 140);
      controller.pause();
      for (var i = 0; i < heartRateLostAfter.inSeconds * 2; i++) {
        second();
      }

      controller.resume();
      for (var i = 0; i < heartRateLostAfter.inSeconds - 1; i++) {
        second();
      }
      expect(c.read(workoutProvider).heartRateStalled, isFalse);

      second();
      expect(c.read(workoutProvider).heartRateStalled, isTrue);
    });

    test('reconnect while paused leaves the new subscription paused', () async {
      final c = container();
      final controller = c.read(workoutProvider.notifier);
      await controller.start(WorkoutType.running, notice: testNotice);
      second(bpm: 140);
      controller.pause();

      await controller.reconnectHeartRate();

      expect(heartRate.listens, 2);
      expect(heartRate.paused, isTrue);
    });

    test('finish while paused still cancels the heart rate', () async {
      final c = container();
      final controller = c.read(workoutProvider.notifier);
      await controller.start(WorkoutType.running, notice: testNotice);
      second(bpm: 140);
      controller.pause();

      await controller.finish();

      expect(heartRate.cancels, 1);
      expect(heartRate.listening, isFalse);
    });
  });
}
