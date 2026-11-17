import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_state.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_store.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/workout_fakes.dart';

final class OrderedWorkoutNotifier implements WorkoutNotifier {
  final log = <String>[];
  final _actions = StreamController<WorkoutNoticeAction>.broadcast(sync: true);

  @override
  Stream<WorkoutNoticeAction> get actions => _actions.stream;

  void tap(WorkoutNoticeAction action) => _actions.add(action);

  @override
  Future<void> show(WorkoutNotice notice) async => log.add('show');

  @override
  Future<void> hide() async => log.add('hide');

  @override
  Future<void> alert(WorkoutAlert alert) async => log.add('alert');

  @override
  Future<void> clearAlert() async => log.add('clearAlert');

  @override
  Future<void> ended(WorkoutEndNotice notice) async => log.add('ended');

  @override
  Future<void> clearEnded() async => log.add('clearEnded');
}

final class ThrowingWorkoutStore implements WorkoutStore {
  @override
  Future<int> save(FinishedWorkout workout, {required DateTime at}) =>
      Future.error(StateError('disk full'));

  @override
  Future<bool> delete(int id) async => false;

  @override
  Future<void> checkpoint(
    WorkoutSession session, {
    required DateTime at,
  }) async {}

  @override
  Future<void> dropCheckpoint(WorkoutSession session) async {}
}

void main() {
  late FakeClock clock;
  late StreamController<void> ticks;
  late FakeHeartRateSource heartRate;
  late FakeLocationSource location;
  late InMemoryWorkoutNotifier notifier;
  late RecordingWorkoutStore store;

  setUp(() {
    clock = FakeClock(workoutStart);
    ticks = StreamController<void>.broadcast(sync: true);
    heartRate = FakeHeartRateSource();
    location = FakeLocationSource();
    notifier = InMemoryWorkoutNotifier();
    store = RecordingWorkoutStore();
  });

  ProviderContainer container({
    WorkoutStore? withStore,
    WorkoutNotifier? withNotifier,
  }) {
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock.call),
        workoutTicksProvider.overrideWithValue(() => ticks.stream),
        liveHeartRateSourceProvider.overrideWithValue(heartRate),
        locationSourceProvider.overrideWithValue(location),
        workoutStoreProvider.overrideWithValue(withStore ?? store),
        workoutNotifierProvider.overrideWithValue(withNotifier ?? notifier),
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

  Future<WorkoutController> started(
    ProviderContainer c,
    WorkoutType type, {
    bool? gps,
  }) async {
    final controller = c.read(workoutProvider.notifier);
    await controller.start(type, notice: testNotice, gps: gps);
    return controller;
  }

  final distanceOrPace = RegExp(r'\d\s?(km|mi|m)\b|/\s?(km|mi)');

  test('workoutNotifierProvider defaults to the in-memory notifier', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(c.read(workoutNotifierProvider), isA<InMemoryWorkoutNotifier>());
  });

  group('1: starting shows the notification once', () {
    test('for a GPS type', () async {
      await started(container(), WorkoutType.running);

      expect(notifier.shown, hasLength(1));
      expect(notifier.shown.single.running, isTrue);
      expect(notifier.shown.single.elapsed, Duration.zero);
      expect(notifier.hides, 0);
    });

    test('for an indoor type', () async {
      await started(container(), WorkoutType.other);

      expect(notifier.shown, hasLength(1));
      expect(notifier.shown.single.running, isTrue);
      expect(notifier.hides, 0);
    });

    test('a refused second start does not show again', () async {
      final c = container();
      final controller = await started(c, WorkoutType.running);
      await controller.start(WorkoutType.walking, notice: testNotice);

      expect(notifier.shown, hasLength(1));
    });
  });

  group('2: ticks show only when the notice changes', () {
    test('a running notice posts at most every 2 seconds', () async {
      await started(container(), WorkoutType.other);

      second(bpm: 120);
      second(bpm: 120);
      second(bpm: 120);

      expect(notifier.shown, hasLength(2));
      expect(notifier.shown.last.elapsed, const Duration(seconds: 2));

      second(bpm: 120);

      expect(notifier.shown, hasLength(3));
      expect(notifier.shown.last.elapsed, const Duration(seconds: 4));
    });

    test('a tick that changes only the text shows again', () async {
      await started(container(), WorkoutType.other);
      second(bpm: 120);
      final before = notifier.shown.length;

      heartRate.emit(150);
      second(bpm: 150);

      expect(notifier.shown.length, before + 1);
      expect(notifier.shown.last.text, contains('150'));
      expect(notifier.shown.last.text, isNot(contains('120')));
    });

    test('a new heart rate inside the interval waits for it', () async {
      await started(container(), WorkoutType.other);
      second(bpm: 120);
      second(bpm: 120);
      final before = notifier.shown.length;

      heartRate.emit(150);
      ticks.add(null);
      second(bpm: 150);

      expect(notifier.shown.length, before);

      second(bpm: 150);

      expect(notifier.shown.length, before + 1);
      expect(notifier.shown.last.text, contains('150'));
    });

    test('disposing a live workout hides', () async {
      final c = container();
      await started(c, WorkoutType.other);
      second(bpm: 120);

      c.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(notifier.hides, 1);
    });

    test('ticks with an identical notice do not show twice', () async {
      await started(container(), WorkoutType.other);
      second(bpm: 120);
      final before = notifier.shown.length;

      ticks
        ..add(null)
        ..add(null)
        ..add(null);

      expect(notifier.shown, hasLength(before));
    });
  });

  group('3: pause and resume flip running', () {
    test('pausing shows running false and resuming running true', () async {
      final controller = await started(container(), WorkoutType.running);
      second(bpm: 140, speed: 3);

      controller.pause();
      expect(notifier.shown.last.running, isFalse);
      expect(notifier.shown.last.elapsed, const Duration(seconds: 1));

      controller.resume();
      expect(notifier.shown.last.running, isTrue);
      expect(notifier.shown, hasLength(3));
    });

    test('ticks while paused keep running false', () async {
      final controller = await started(container(), WorkoutType.other);
      second(bpm: 140);
      controller.pause();

      second();
      second();

      expect(notifier.shown.every((n) => n.elapsed.inSeconds <= 1), isTrue);
      expect(notifier.shown.last.running, isFalse);
    });
  });

  group('4: the notification is hidden when the workout ends', () {
    test('finish hides', () async {
      final controller = await started(container(), WorkoutType.running);
      second(bpm: 140, speed: 3);
      expect(notifier.hides, 0);

      await controller.finish();

      expect(notifier.hides, 1);
    });

    test('discard hides', () async {
      final controller = await started(container(), WorkoutType.walking);
      second(bpm: 120, speed: 1.5);

      await controller.discard();

      expect(notifier.hides, 1);
    });

    test('a store that throws still hides', () async {
      final c = container(withStore: ThrowingWorkoutStore());
      final controller = await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);

      await controller.finish();

      expect(c.read(workoutProvider).save, WorkoutSave.failed);
      expect(notifier.hides, 1);
    });

    test('nothing is shown after the last hide on finish', () async {
      final ordered = OrderedWorkoutNotifier();
      final controller = await started(
        container(withNotifier: ordered),
        WorkoutType.running,
      );
      second(bpm: 140, speed: 3);

      await controller.finish();
      second();
      await pumpEventQueue();

      expect(ordered.log.sublist(ordered.log.indexOf('hide')), [
        'hide',
        'ended',
      ]);
      expect(ordered.log.where((e) => e == 'hide'), hasLength(1));
    });

    test('nothing is shown after the last hide on discard', () async {
      final ordered = OrderedWorkoutNotifier();
      final controller = await started(
        container(withNotifier: ordered),
        WorkoutType.other,
      );
      second(bpm: 140);

      await controller.discard();
      second();
      await pumpEventQueue();

      expect(ordered.log.last, 'hide');
    });

    test('nothing is shown after the last hide when the save fails', () async {
      final ordered = OrderedWorkoutNotifier();
      final controller = await started(
        container(withStore: ThrowingWorkoutStore(), withNotifier: ordered),
        WorkoutType.other,
      );
      second(bpm: 140);

      await controller.finish();
      await pumpEventQueue();

      expect(ordered.log.sublist(ordered.log.lastIndexOf('hide')), [
        'hide',
        'ended',
      ]);
    });
  });

  group('5: notification actions drive the workout', () {
    test('pause then resume', () async {
      final c = container();
      await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);

      notifier.tap(WorkoutNoticeAction.pause);
      await pumpEventQueue();
      expect(c.read(workoutProvider).status, WorkoutStatus.paused);
      expect(notifier.shown.last.running, isFalse);

      notifier.tap(WorkoutNoticeAction.resume);
      await pumpEventQueue();
      expect(c.read(workoutProvider).status, WorkoutStatus.running);
      expect(notifier.shown.last.running, isTrue);
    });

    test('N3: a stop tap on a running workout pauses and asks', () async {
      final c = container();
      await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);
      second(bpm: 141, speed: 3);

      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      final state = c.read(workoutProvider);
      expect(state.status, WorkoutStatus.paused);
      expect(state.live, isTrue);
      expect(store.saved, isEmpty);
      expect(notifier.hides, 0);
      final asking = notifier.shown.last;
      expect(asking.confirming, isTrue);
      expect(asking.title, 'End and save the workout?');
      expect(asking.running, isFalse);
      expect(asking.elapsed, const Duration(seconds: 2));
    });

    test(
      'N3: a stop tap while paused asks at once and saves nothing',
      () async {
        final c = container();
        final controller = await started(c, WorkoutType.other);
        second(bpm: 140);
        controller.pause();

        notifier.tap(WorkoutNoticeAction.stop);
        await pumpEventQueue();

        expect(c.read(workoutProvider).status, WorkoutStatus.paused);
        expect(store.saved, isEmpty);
        expect(notifier.shown.last.confirming, isTrue);
        expect(notifier.shown.last.title, 'End and save the workout?');
      },
    );
  });

  group('6: a failing notifier never stops the workout', () {
    test('start, tick, pause, resume and finish all go through', () async {
      notifier.failing = true;
      final c = container();
      final controller = await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);
      controller.pause();
      expect(c.read(workoutProvider).status, WorkoutStatus.paused);
      controller.resume();
      second(bpm: 141, speed: 3);

      await controller.finish();
      await pumpEventQueue();

      final state = c.read(workoutProvider);
      expect(state.status, WorkoutStatus.finished);
      expect(state.save, WorkoutSave.saved);
      expect(state.snapshot!.elapsed, const Duration(seconds: 2));
      expect(store.saved, hasLength(1));
    });

    test('a notifier that starts failing mid workout is survived', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);

      notifier.failing = true;
      second(bpm: 141);
      controller
        ..pause()
        ..resume();
      await controller.discard();
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.discarded);
    });

    test('a failing hide does not block the save', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);
      notifier.failing = true;

      await controller.finish();

      expect(c.read(workoutProvider).save, WorkoutSave.saved);
      expect(store.saved, hasLength(1));
    });

    test('actions still work after the notifier recovers', () async {
      notifier.failing = true;
      final c = container();
      await started(c, WorkoutType.other);
      notifier
        ..failing = false
        ..tap(WorkoutNoticeAction.pause);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.paused);
    });
  });

  group('7: the notice shows only the fields that apply', () {
    test('an indoor workout has no distance and no pace', () async {
      await started(container(), WorkoutType.other);
      for (var i = 0; i < 5; i++) {
        second(bpm: 147);
      }

      final text = notifier.shown.last.text;
      expect(text, contains('147'));
      expect(text, isNot(contains(distanceOrPace)));
    });

    test('a GPS type with GPS switched off has none either', () async {
      await started(container(), WorkoutType.running, gps: false);
      for (var i = 0; i < 5; i++) {
        second(bpm: 147);
      }

      final text = notifier.shown.last.text;
      expect(text, contains('147'));
      expect(text, isNot(contains(distanceOrPace)));
      expect(text.replaceAll('147', ''), isNot(contains(RegExp(r'\d'))));
    });

    test('with no heart rate yet an indoor notice has no heart rate', () async {
      await started(container(), WorkoutType.other);
      second();
      second();

      for (final notice in notifier.shown) {
        expect(notice.text, 'Recording the time');
      }
    });

    test('a GPS workout shows more than the heart rate', () async {
      await started(container(), WorkoutType.running);
      location.emit(fixAt(Duration.zero, northMeters: 0));
      for (var i = 0; i < 10; i++) {
        second(bpm: 147, speed: 3);
      }

      final text = notifier.shown.last.text;
      expect(text, contains('147'));
      expect(text.replaceAll('147', ''), contains(RegExp(r'\d')));
    });

    test('the heart rate leaves the text when the snapshot has none', () async {
      final controller = await started(container(), WorkoutType.other);
      second(bpm: 147);
      second(bpm: 147);
      expect(notifier.shown.last.text, contains('147'));

      controller.pause();

      expect(notifier.shown.last.text, isNot(contains('147')));
    });

    test(
      'elapsed equals the snapshot elapsed and running tracks status',
      () async {
        final c = container();
        final controller = await started(c, WorkoutType.other);
        for (var i = 0; i < 8; i++) {
          second(bpm: 130);
        }
        expect(
          notifier.shown.last.elapsed,
          c.read(workoutProvider).snapshot!.elapsed,
        );
        expect(notifier.shown.last.elapsed, const Duration(seconds: 8));

        controller.pause();
        expect(notifier.shown.last.running, isFalse);
        expect(notifier.shown.last.elapsed, const Duration(seconds: 8));
      },
    );
  });

  group('10: lost signals change the text', () {
    test('a ring silent past the hold shows no heart rate', () async {
      await started(container(), WorkoutType.other);
      second(bpm: 140);
      second(bpm: 140);
      expect(notifier.shown.last.text, contains('140'));

      for (var i = 0; i < 32; i++) {
        second();
      }

      expect(notifier.shown.last.text, startsWith('-- bpm'));
      expect(notifier.shown.last.text, isNot(contains('140')));
    });

    test('a GPS failure replaces distance and pace', () async {
      await started(container(), WorkoutType.running);
      location.emit(fixAt(Duration.zero, northMeters: 0));
      for (var i = 0; i < 6; i++) {
        second(bpm: 147, speed: 3);
      }
      expect(notifier.shown.last.text, contains(distanceOrPace));

      location.fail(const LocationUnavailable(LocationProblem.failed));
      second(bpm: 147);
      second(bpm: 147);

      expect(notifier.shown.last.text, contains('GPS signal lost'));
      expect(notifier.shown.last.text, isNot(contains(distanceOrPace)));
    });
  });

  group('9: a late tap does nothing', () {
    test('after finish', () async {
      final c = container();
      final controller = await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);
      await controller.finish();
      final shown = notifier.shown.length;
      final hides = notifier.hides;

      notifier
        ..tap(WorkoutNoticeAction.pause)
        ..tap(WorkoutNoticeAction.resume)
        ..tap(WorkoutNoticeAction.stop)
        ..tap(WorkoutNoticeAction.save)
        ..tap(WorkoutNoticeAction.keep)
        ..tap(WorkoutNoticeAction.reconnect);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.finished);
      expect(store.saved, hasLength(1));
      expect(notifier.shown, hasLength(shown));
      expect(notifier.hides, hides);
      expect(heartRate.listens, 1);
    });

    test('after discard', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);
      await controller.discard();

      notifier
        ..tap(WorkoutNoticeAction.resume)
        ..tap(WorkoutNoticeAction.stop)
        ..tap(WorkoutNoticeAction.save)
        ..tap(WorkoutNoticeAction.keep);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.discarded);
      expect(store.saved, isEmpty);
    });

    test('before any workout started', () async {
      final c = container()..read(workoutProvider);

      notifier
        ..tap(WorkoutNoticeAction.stop)
        ..tap(WorkoutNoticeAction.save)
        ..tap(WorkoutNoticeAction.keep)
        ..tap(WorkoutNoticeAction.reconnect);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.idle);
      expect(store.saved, isEmpty);
      expect(heartRate.listens, 0);
    });

    test('after the container is disposed', () async {
      final c = container();
      await started(c, WorkoutType.other);
      c.dispose();

      notifier
        ..tap(WorkoutNoticeAction.stop)
        ..tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      expect(store.saved, isEmpty);
    });
  });

  group('N3: save after the question', () {
    test('a save tap saves exactly once and hides', () async {
      final c = container();
      await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);
      second(bpm: 141, speed: 3);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();
      for (var i = 0; i < 10; i++) {
        second();
      }

      notifier.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      final state = c.read(workoutProvider);
      expect(state.status, WorkoutStatus.finished);
      expect(state.save, WorkoutSave.saved);
      expect(store.saved, hasLength(1));
      expect(store.saved.single.elapsed, const Duration(seconds: 2));
      expect(notifier.hides, 1);
    });

    test('a second save tap saves nothing', () async {
      final c = container();
      await started(c, WorkoutType.other);
      second(bpm: 140);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      notifier.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();
      notifier.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      expect(store.saved, hasLength(1));
      expect(notifier.hides, 1);
    });

    test('two save taps in the same turn save once', () async {
      final c = container();
      await started(c, WorkoutType.other);
      second(bpm: 140);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      notifier
        ..tap(WorkoutNoticeAction.save)
        ..tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      expect(store.saved, hasLength(1));
    });

    test('nothing is shown after the last hide on a save tap', () async {
      final ordered = OrderedWorkoutNotifier();
      await started(container(withNotifier: ordered), WorkoutType.other);
      second(bpm: 140);
      ordered.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      ordered.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();
      second();
      await pumpEventQueue();

      expect(ordered.log.sublist(ordered.log.indexOf('hide')), [
        'hide',
        'ended',
      ]);
      expect(ordered.log.where((e) => e == 'hide'), hasLength(1));
    });

    test('a store that throws on a save tap still hides', () async {
      final c = container(withStore: ThrowingWorkoutStore());
      await started(c, WorkoutType.other);
      second(bpm: 140);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      notifier.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      expect(c.read(workoutProvider).save, WorkoutSave.failed);
      expect(notifier.hides, 1);
    });

    test('a failing notifier still asks and saves', () async {
      notifier.failing = true;
      final c = container();
      await started(c, WorkoutType.other);
      second(bpm: 140);

      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();
      expect(store.saved, isEmpty);
      expect(c.read(workoutProvider).status, WorkoutStatus.paused);

      notifier.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.finished);
      expect(store.saved, hasLength(1));
    });

    test('a save tap with no question pending saves nothing', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);

      notifier.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();
      expect(c.read(workoutProvider).status, WorkoutStatus.running);

      controller.pause();
      notifier.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.paused);
      expect(store.saved, isEmpty);
      expect(notifier.hides, 0);
    });
  });

  group('N3: keep returns to the state before End', () {
    test('keep after End on a running workout resumes it', () async {
      final c = container();
      await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      notifier.tap(WorkoutNoticeAction.keep);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.running);
      expect(notifier.shown.last.running, isTrue);
      expect(notifier.shown.last.confirming, isFalse);
      expect(store.saved, isEmpty);
      expect(notifier.hides, 0);
    });

    test('keep after End on a paused workout leaves it paused', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);
      controller.pause();
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      notifier.tap(WorkoutNoticeAction.keep);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.paused);
      expect(notifier.shown.last.running, isFalse);
      expect(notifier.shown.last.confirming, isFalse);
      expect(notifier.shown.last.title, isNot('End and save the workout?'));
      expect(store.saved, isEmpty);
    });

    test('a second stop tap does not forget the workout was running', () async {
      final c = container();
      await started(c, WorkoutType.other);
      second(bpm: 140);

      notifier
        ..tap(WorkoutNoticeAction.stop)
        ..tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();
      expect(store.saved, isEmpty);

      notifier.tap(WorkoutNoticeAction.keep);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.running);
    });

    test('a keep tap with no question pending changes nothing', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);
      controller.pause();
      final shown = notifier.shown.length;

      notifier.tap(WorkoutNoticeAction.keep);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.paused);
      expect(notifier.shown, hasLength(shown));
    });

    test('End can be asked again after keep', () async {
      final c = container();
      await started(c, WorkoutType.other);
      second(bpm: 140);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();
      notifier.tap(WorkoutNoticeAction.keep);
      await pumpEventQueue();
      second(bpm: 140);

      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.paused);
      expect(notifier.shown.last.confirming, isTrue);
      expect(store.saved, isEmpty);
    });
  });

  group('N3: the question holds pause and resume', () {
    test('pause and resume taps during the question change nothing', () async {
      final c = container();
      await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();
      final shown = notifier.shown.length;

      notifier
        ..tap(WorkoutNoticeAction.resume)
        ..tap(WorkoutNoticeAction.pause);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.paused);
      expect(notifier.shown, hasLength(shown));
      expect(notifier.shown.last.confirming, isTrue);
      expect(store.saved, isEmpty);

      notifier.tap(WorkoutNoticeAction.keep);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.running);
    });

    test('ticks during the question keep it on the notice', () async {
      await started(container(), WorkoutType.other);
      second(bpm: 140);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      second();
      second();
      second();

      expect(notifier.shown.last.confirming, isTrue);
    });

    test('resume from the app clears the question', () async {
      final c = container();
      final controller = await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      controller.resume();

      expect(c.read(workoutProvider).status, WorkoutStatus.running);
      expect(notifier.shown.last.confirming, isFalse);
      expect(notifier.shown.last.running, isTrue);
    });

    test('a save tap after resume from the app saves nothing', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();
      controller.resume();

      notifier.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.running);
      expect(store.saved, isEmpty);
    });

    test('finish from the app during the question saves once', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      await controller.finish();
      notifier.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.finished);
      expect(store.saved, hasLength(1));
      expect(notifier.hides, 1);
    });

    test('discard from the app during the question saves nothing', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      await controller.discard();
      notifier.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.discarded);
      expect(store.saved, isEmpty);
    });
  });

  group('N3: reconnect from the notice', () {
    test('a lost ring flags the notice for Reconnect', () async {
      await started(container(), WorkoutType.other);
      second(bpm: 140);
      second(bpm: 140);
      expect(notifier.shown.last.ringLost, isFalse);

      for (var i = 0; i < 32; i++) {
        second();
      }

      expect(notifier.shown.last.ringLost, isTrue);
    });

    test('a reconnect tap restarts the heart rate stream', () async {
      final c = container();
      await started(c, WorkoutType.other);
      second(bpm: 140);
      for (var i = 0; i < 32; i++) {
        second();
      }
      expect(c.read(workoutProvider).heartRateStalled, isTrue);
      expect(heartRate.listens, 1);

      notifier.tap(WorkoutNoticeAction.reconnect);
      await pumpEventQueue();

      expect(heartRate.cancels, 1);
      expect(heartRate.listens, 2);
      expect(heartRate.listening, isTrue);
      expect(c.read(workoutProvider).heartRateStalled, isFalse);
      expect(c.read(workoutProvider).status, WorkoutStatus.running);
    });

    test('two reconnect taps restart the stream once', () async {
      await started(container(), WorkoutType.other);
      second(bpm: 140);

      notifier
        ..tap(WorkoutNoticeAction.reconnect)
        ..tap(WorkoutNoticeAction.reconnect);
      await pumpEventQueue();

      expect(heartRate.listens, 2);
    });
  });
}
