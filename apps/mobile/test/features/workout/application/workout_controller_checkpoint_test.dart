import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_state.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_store.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_store.dart';

import '../../../helpers/database.dart';
import '../../../helpers/workout_fakes.dart';

DateTime at(int seconds) => workoutStart.add(Duration(seconds: seconds));

// Logs every call and keeps each checkpoint write so a test can wait for the
// writes the controller does not await.
final class _TrackedStore implements WorkoutStore {
  new(this._inner);

  final WorkoutStore _inner;
  final log = <String>[];
  final _pending = <Future<void>>[];
  Completer<void>? gate;
  bool failCheckpoints = false;

  int get checkpoints => log.where((entry) => entry == 'checkpoint').length;

  Future<void> settle() async {
    while (_pending.isNotEmpty) {
      final pending = List.of(_pending);
      _pending.clear();
      await Future.wait(pending);
    }
  }

  @override
  Future<void> checkpoint(WorkoutSession session, {required DateTime at}) {
    log.add('checkpoint');
    if (failCheckpoints) return Future.error(StateError('disk full'));
    final write = _write(session, at);
    _pending.add(write);
    return write;
  }

  Future<void> _write(WorkoutSession session, DateTime at) async {
    await _inner.checkpoint(session, at: at);
    await gate?.future;
    log.add('checkpoint done');
  }

  @override
  Future<void> dropCheckpoint(WorkoutSession session) {
    log.add('drop');
    final drop = _inner.dropCheckpoint(session);
    _pending.add(drop);
    return drop;
  }

  @override
  Future<int> save(FinishedWorkout workout, {required DateTime at}) {
    log.add('save');
    return _inner.save(workout, at: at);
  }

  @override
  Future<bool> delete(int id) => _inner.delete(id);
}

void main() {
  late AppDatabase db;
  late _TrackedStore store;
  late FakeClock clock;
  late StreamController<void> ticks;
  late FakeHeartRateSource heartRate;
  late FakeLocationSource location;
  late InMemoryWorkoutNotifier notifier;
  var meters = 0.0;

  setUp(() {
    db = memoryDatabase();
    store = _TrackedStore(DriftWorkoutStore(db));
    clock = FakeClock(workoutStart);
    ticks = StreamController<void>.broadcast(sync: true);
    heartRate = FakeHeartRateSource();
    location = FakeLocationSource();
    notifier = InMemoryWorkoutNotifier();
    meters = 0;
  });

  tearDown(() => ticks.close());

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock.call),
        workoutTicksProvider.overrideWithValue(() => ticks.stream),
        liveHeartRateSourceProvider.overrideWithValue(heartRate),
        locationSourceProvider.overrideWithValue(location),
        workoutStoreProvider.overrideWithValue(store),
        workoutNotifierProvider.overrideWithValue(notifier),
        userProfileStoreProvider.overrideWithValue(
          InMemoryUserProfileStore(
            const UserProfile(birthYear: 1996, weightKilograms: 70),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  void run(int seconds) {
    for (var i = 0; i < seconds; i++) {
      clock.advance(const Duration(seconds: 1));
      meters += 3;
      location.emit(
        fixAt(clock.now.difference(workoutStart), northMeters: meters),
      );
      heartRate.emit(140 + i % 10);
      ticks.add(null);
    }
  }

  Future<WorkoutController> started(ProviderContainer c) async {
    final controller = c.read(workoutProvider.notifier);
    await controller.start(WorkoutType.running, notice: testNotice);
    location.emit(fixAt(Duration.zero, northMeters: 0));
    return controller;
  }

  Future<WorkoutRow> single() => db.select(db.workouts).getSingle();

  test('59 ticks write no row, 60 write one open row, 120 keep that row and '
      'append its children once', () async {
    await started(container());

    run(59);
    await store.settle();
    expect(store.checkpoints, 0);
    expect(await rowCount(db, 'workouts'), 0);

    run(1);
    await store.settle();
    final first = await single();
    expect(first.endUtcMs, isNull);
    expect(first.checkpointUtcMs, at(60).utcMs);
    expect(first.elapsedMs, 60000);
    expect(await rowCount(db, 'workout_hr_samples'), 60);
    expect(await rowCount(db, 'workout_route_points'), 61);

    run(60);
    await store.settle();
    expect(store.checkpoints, 2);
    expect(await rowCount(db, 'workouts'), 1);
    final second = await single();
    expect(second.id, first.id);
    expect(second.endUtcMs, isNull);
    expect(second.checkpointUtcMs, at(120).utcMs);
    expect(await rowCount(db, 'workout_hr_samples'), 120);
    expect(await rowCount(db, 'workout_route_points'), 121);
    expect(await rowCount(db, 'health_outbox'), 0);
  });

  test('pause writes at once with the end at the pause, and 120 paused ticks '
      'write nothing more', () async {
    final controller = await started(container());
    run(30);
    await store.settle();
    expect(await rowCount(db, 'workouts'), 0);

    controller.pause();
    await store.settle();
    final paused = await single();
    expect(store.checkpoints, 1);
    expect(paused.endUtcMs, isNull);
    expect(paused.checkpointUtcMs, at(30).utcMs);
    expect(paused.elapsedMs, 30000);

    run(120);
    await store.settle();
    expect(store.checkpoints, 1);
    expect(await single(), paused);
  });

  test('End from the notification writes the pause checkpoint once and Save '
      'closes it', () async {
    final c = container();
    await started(c);
    run(30);

    notifier.tap(WorkoutNoticeAction.stop);
    await store.settle();
    final asked = await single();
    expect(store.checkpoints, 1);
    expect(asked.checkpointUtcMs, at(30).utcMs);
    run(90);
    await store.settle();
    expect(store.checkpoints, 1);

    notifier.tap(WorkoutNoticeAction.save);
    for (var turn = 0; turn < 50; turn++) {
      if (c.read(workoutProvider).save == WorkoutSave.saved) break;
      await pumpEventQueue();
    }

    final saved = await single();
    expect(c.read(workoutProvider).save, WorkoutSave.saved);
    expect(saved.id, asked.id);
    expect(saved.endUtcMs, isNotNull);
    expect(saved.checkpointUtcMs, isNull);
  });

  test('save after a checkpoint keeps the id, sets the end, clears the '
      'checkpoint and queues one outbox row', () async {
    final c = container();
    final controller = await started(c);
    run(60);
    await store.settle();
    final open = await single();
    run(30);

    await controller.finish();

    final state = c.read(workoutProvider);
    expect(state.save, WorkoutSave.saved);
    expect(state.workoutId, open.id);
    final row = await single();
    expect(row.id, open.id);
    expect(row.endUtcMs, at(90).utcMs);
    expect(row.checkpointUtcMs, isNull);
    expect(row.elapsedMs, 90000);
    expect(await rowCount(db, 'workout_hr_samples'), 90);
    expect(await rowCount(db, 'health_outbox'), 1);
  });

  test('discard after a checkpoint leaves no workout rows', () async {
    final controller = await started(container());
    run(60);
    await store.settle();
    expect(await rowCount(db, 'workouts'), 1);

    await controller.discard();
    await store.settle();

    expect(store.log, contains('drop'));
    expect(await rowCount(db, 'workouts'), 0);
    expect(await rowCount(db, 'workout_hr_samples'), 0);
    expect(await rowCount(db, 'workout_route_points'), 0);
    expect(await rowCount(db, 'health_outbox'), 0);
  });

  test('a clock set back 30 min keeps the one minute cadence', () async {
    await started(container());
    run(60);
    await store.settle();
    expect(store.checkpoints, 1);

    clock.advance(const Duration(minutes: -30));
    run(59);
    await store.settle();
    expect(store.checkpoints, 1);
    run(1);
    await store.settle();
    expect(store.checkpoints, 2);
    expect(await rowCount(db, 'workouts'), 1);
  });

  test('finish waits for a checkpoint still in flight before saving', () async {
    final c = container();
    final controller = await started(c);
    store.gate = Completer<void>();
    run(60);

    final finishing = controller.finish();
    await pumpEventQueue();
    expect(store.log, ['checkpoint']);

    store.gate!.complete();
    await finishing;

    expect(store.log, ['checkpoint', 'checkpoint done', 'save']);
    final row = await single();
    expect(c.read(workoutProvider).workoutId, row.id);
    expect(row.endUtcMs, at(60).utcMs);
    expect(row.checkpointUtcMs, isNull);
  });

  test(
    'a failing checkpoint neither stops the workout nor blocks its save',
    () async {
      final c = container();
      final controller = await started(c);
      store.failCheckpoints = true;

      run(130);
      expect(store.checkpoints, greaterThan(0));
      expect(c.read(workoutProvider).status, WorkoutStatus.running);

      await controller.finish();

      expect(c.read(workoutProvider).save, WorkoutSave.saved);
      final row = await single();
      expect(row.endUtcMs, at(130).utcMs);
      expect(await rowCount(db, 'health_outbox'), 1);
    },
  );
}
