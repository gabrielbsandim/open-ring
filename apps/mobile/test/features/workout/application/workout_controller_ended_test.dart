import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_lock_providers.dart';
import 'package:open_ring/features/workout/application/workout_state.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_store.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/workout_fakes.dart';

const _summaryLink = 'openring://widget/activity/workout-summary';

final class _OrderedNotifier implements WorkoutNotifier {
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

// Throws before returning a future, the harder case for the controller.
final class _ThrowingEndedNotifier implements WorkoutNotifier {
  final shown = <WorkoutNotice>[];
  final _actions = StreamController<WorkoutNoticeAction>.broadcast(sync: true);
  int endedCalls = 0;
  int clearCalls = 0;

  @override
  Stream<WorkoutNoticeAction> get actions => _actions.stream;

  @override
  Future<void> show(WorkoutNotice notice) async => shown.add(notice);

  @override
  Future<void> hide() async {}

  @override
  Future<void> alert(WorkoutAlert alert) async {}

  @override
  Future<void> clearAlert() async {}

  @override
  Future<void> ended(WorkoutEndNotice notice) {
    endedCalls++;
    throw const WorkoutNotifierFailure();
  }

  @override
  Future<void> clearEnded() {
    clearCalls++;
    throw const WorkoutNotifierFailure();
  }
}

final class _ThrowingStore implements WorkoutStore {
  @override
  Future<int> save(FinishedWorkout workout, {required DateTime at}) =>
      Future.error(StateError('disk full'));

  @override
  Future<bool> delete(int id) async => false;
}

final class _DeferredStore implements WorkoutStore {
  final pending = <Completer<int>>[];

  @override
  Future<int> save(FinishedWorkout workout, {required DateTime at}) {
    final completer = Completer<int>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<bool> delete(int id) async => false;
}

void main() {
  final en = workoutLocationNotice(lookupAppLocalizations(const Locale('en')));
  final labels = testNotice.live;

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

  tearDown(() => ticks.close());

  ProviderContainer container({
    WorkoutStore? withStore,
    WorkoutNotifier? withNotifier,
    UnitSystem units = UnitSystem.metric,
  }) {
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock.call),
        workoutTicksProvider.overrideWithValue(() => ticks.stream),
        liveHeartRateSourceProvider.overrideWithValue(heartRate),
        locationSourceProvider.overrideWithValue(location),
        workoutStoreProvider.overrideWithValue(withStore ?? store),
        workoutNotifierProvider.overrideWithValue(withNotifier ?? notifier),
        currentUnitSystemProvider.overrideWithValue(units),
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

  setUp(() => meters = 0);

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

  Future<WorkoutController> started(
    ProviderContainer c,
    WorkoutType type, {
    LocationNotice notice = testNotice,
  }) async {
    final controller = c.read(workoutProvider.notifier);
    await controller.start(type, notice: notice);
    return controller;
  }

  group('1: a saved workout posts the saved notice', () {
    test('finish posts one saved notice linking to the stored id', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);
      second(bpm: 140);

      await controller.finish();
      await pumpEventQueue();

      expect(c.read(workoutProvider).save, WorkoutSave.saved);
      expect(c.read(workoutProvider).workoutId, 1);
      final notice = notifier.endedNotices.single;
      expect(notice.title, labels.savedTitle);
      expect(notice.action, labels.viewSummary);
      expect(notice.text, contains('0:02'));
      expect(notice.link, '$_summaryLink/1');
    });

    test('the text follows the imperial setting', () async {
      final c = container(units: UnitSystem.imperial);
      final controller = await started(c, WorkoutType.running, notice: en);
      for (var i = 0; i < 20; i++) {
        second(bpm: 140, speed: 3);
      }

      await controller.finish();
      await pumpEventQueue();

      final text = notifier.endedNotices.single.text;
      expect(text, startsWith('Running · 0:20'));
      expect(text, contains(' mi'));
      expect(text, isNot(contains('km')));
    });

    test('the saved notice posts after the live notice is hidden', () async {
      final ordered = _OrderedNotifier();
      final controller = await started(
        container(withNotifier: ordered),
        WorkoutType.running,
      );
      second(bpm: 140, speed: 3);

      await controller.finish();
      await pumpEventQueue();

      final afterHide = ordered.log.sublist(ordered.log.lastIndexOf('hide'));
      expect(afterHide, ['hide', 'ended']);
    });
  });

  group('the lock screen heart rate setting reaches the notice', () {
    test('off sends the text with no heart rate', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      await c.read(workoutLockHeartRateProvider.notifier).set(show: false);
      second(bpm: 140);
      second(bpm: 140);

      await controller.finish();
      await pumpEventQueue();

      final notice = notifier.endedNotices.single;
      expect(notice.text, '0:02 · Avg HR 140');
      expect(notice.publicText, '0:02');
    });

    test('on sends no lock screen text', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      await c.read(workoutLockHeartRateProvider.notifier).set(show: true);
      second(bpm: 140);

      await controller.finish();
      await pumpEventQueue();

      expect(notifier.endedNotices.single.publicText, isNull);
    });
  });

  group('3: a store that throws posts the failed notice', () {
    test('one failed notice with Open and the summary link', () async {
      final c = container(withStore: _ThrowingStore());
      final controller = await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);

      await controller.finish();
      await pumpEventQueue();

      expect(c.read(workoutProvider).save, WorkoutSave.failed);
      final notice = notifier.endedNotices.single;
      expect(notice.title, labels.failedTitle);
      expect(notice.text, labels.failedText);
      expect(notice.action, labels.open);
      expect(notice.link, endsWith('workout-summary'));
      expect(notice.link, _summaryLink);
      expect(notice.failed, isTrue);
    });

    test('the failed notice posts after the live notice is hidden', () async {
      final ordered = _OrderedNotifier();
      final controller = await started(
        container(withStore: _ThrowingStore(), withNotifier: ordered),
        WorkoutType.other,
      );
      second(bpm: 140);

      await controller.finish();
      await pumpEventQueue();

      final afterHide = ordered.log.sublist(ordered.log.lastIndexOf('hide'));
      expect(afterHide, ['hide', 'ended']);
    });
  });

  group('4: a retry that saves replaces the failed notice', () {
    test('failure then a good saveAgain leaves 2, the last saved', () async {
      final c = container(withStore: FlakyWorkoutStore(store));
      final controller = await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);

      await controller.finish();
      await pumpEventQueue();
      expect(c.read(workoutProvider).save, WorkoutSave.failed);

      await controller.saveAgain();
      await pumpEventQueue();

      expect(c.read(workoutProvider).save, WorkoutSave.saved);
      expect(notifier.endedNotices, hasLength(2));
      expect(notifier.endedNotices.first.title, labels.failedTitle);
      expect(notifier.endedNotices.last.title, labels.savedTitle);
      expect(notifier.endedNotices.last.action, labels.viewSummary);
      expect(notifier.endedNotices.last.link, '$_summaryLink/1');
    });

    test('two failures post two failed notices', () async {
      final c = container(withStore: FlakyWorkoutStore(store, failures: 2));
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);

      await controller.finish();
      await controller.saveAgain();
      await pumpEventQueue();

      expect(c.read(workoutProvider).save, WorkoutSave.failed);
      expect(notifier.endedNotices, hasLength(2));
      expect(
        notifier.endedNotices.map((n) => n.title),
        everyElement(labels.failedTitle),
      );
    });
  });

  group('5: a failing notifier loses only the notice', () {
    test('the save state is still saved and nothing throws', () async {
      notifier.failing = true;
      final c = container();
      final controller = await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);

      await controller.finish();
      await pumpEventQueue();

      final state = c.read(workoutProvider);
      expect(state.status, WorkoutStatus.finished);
      expect(state.save, WorkoutSave.saved);
      expect(state.workoutId, 1);
      expect(store.saved, hasLength(1));
      expect(notifier.endedNotices, isEmpty);
    });

    test('a failed save is still failed and nothing throws', () async {
      notifier.failing = true;
      final c = container(withStore: _ThrowingStore());
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);

      await controller.finish();
      await pumpEventQueue();

      expect(c.read(workoutProvider).save, WorkoutSave.failed);
    });

    test('a notifier that throws before returning changes nothing', () async {
      final throwing = _ThrowingEndedNotifier();
      final c = container(
        withStore: FlakyWorkoutStore(store),
        withNotifier: throwing,
      );
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);

      expect(throwing.clearCalls, 1);
      expect(throwing.shown, isNotEmpty);
      expect(c.read(workoutProvider).status, WorkoutStatus.running);

      await controller.finish();
      await controller.saveAgain();
      controller.summaryOpened();
      await pumpEventQueue();

      expect(throwing.endedCalls, 2);
      expect(throwing.clearCalls, 2);
      expect(c.read(workoutProvider).save, WorkoutSave.saved);
      expect(c.read(workoutProvider).workoutId, 1);
    });
  });

  group('6: opening the summary clears the notice', () {
    test('summaryOpened clears once and keeps the state', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);
      await controller.finish();
      await pumpEventQueue();
      final before = notifier.endedClears;
      final state = c.read(workoutProvider);

      controller.summaryOpened();
      await pumpEventQueue();

      expect(notifier.endedClears, before + 1);
      expect(c.read(workoutProvider), same(state));
    });

    test('summaryOpened with no workout clears and throws nothing', () async {
      final c = container();
      final controller = c.read(workoutProvider.notifier)..summaryOpened();
      await pumpEventQueue();

      expect(notifier.endedClears, 1);
      expect(controller.session, isNull);
    });

    test('summaryOpened with a failing notifier throws nothing', () async {
      notifier.failing = true;
      final c = container();

      c.read(workoutProvider.notifier).summaryOpened();
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.idle);
    });
  });

  group('7: start clears the last notice', () {
    test('clearEnded comes before the first show', () async {
      final ordered = _OrderedNotifier();
      await started(container(withNotifier: ordered), WorkoutType.running);

      expect(ordered.log, contains('show'));
      expect(ordered.log.first, 'clearEnded');
      expect(
        ordered.log.indexOf('clearEnded'),
        lessThan(ordered.log.indexOf('show')),
      );
    });

    test('each start clears once', () async {
      final c = container();
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);
      await controller.finish();
      await pumpEventQueue();
      expect(notifier.endedClears, 1);

      await controller.start(WorkoutType.walking, notice: testNotice);

      expect(notifier.endedClears, 2);
      expect(notifier.endedNotices, hasLength(1));
    });

    test('a refused second start does not clear again', () async {
      final c = container();
      final controller = await started(c, WorkoutType.running);

      await controller.start(WorkoutType.walking, notice: testNotice);

      expect(notifier.endedClears, 1);
    });
  });

  group('a save that finishes after a new start', () {
    test('posts no saved notice over the new workout', () async {
      final deferred = _DeferredStore();
      final ordered = _OrderedNotifier();
      final c = container(withStore: deferred, withNotifier: ordered);
      final controller = await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);
      final finishing = controller.finish();
      await pumpEventQueue();
      expect(c.read(workoutProvider).save, WorkoutSave.saving);

      await controller.start(WorkoutType.walking, notice: testNotice);
      deferred.pending.single.complete(1);
      await finishing;
      await pumpEventQueue();

      expect(c.read(workoutProvider).live, isTrue);
      final sinceStart = ordered.log.sublist(
        ordered.log.lastIndexOf('clearEnded'),
      );
      expect(sinceStart, isNot(contains('ended')));
    });

    test('posts no failed notice over the new workout', () async {
      final deferred = _DeferredStore();
      final ordered = _OrderedNotifier();
      final c = container(withStore: deferred, withNotifier: ordered);
      final controller = await started(c, WorkoutType.other);
      second(bpm: 140);
      final finishing = controller.finish();
      await pumpEventQueue();

      await controller.start(WorkoutType.walking, notice: testNotice);
      deferred.pending.single.completeError(StateError('disk full'));
      await finishing;
      await pumpEventQueue();

      expect(c.read(workoutProvider).live, isTrue);
      final sinceStart = ordered.log.sublist(
        ordered.log.lastIndexOf('clearEnded'),
      );
      expect(sinceStart, isNot(contains('ended')));
    });
  });

  group('8: the notice Save action posts once', () {
    test('stop then save posts exactly 1 ended notice', () async {
      final c = container();
      await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      notifier.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      expect(c.read(workoutProvider).save, WorkoutSave.saved);
      expect(notifier.endedNotices, hasLength(1));
      expect(notifier.endedNotices.single.title, labels.savedTitle);
    });

    test('two save taps in the same turn still post 1', () async {
      await started(container(), WorkoutType.other);
      second(bpm: 140);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      notifier
        ..tap(WorkoutNoticeAction.save)
        ..tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      expect(notifier.endedNotices, hasLength(1));
    });
  });

  group('9: discard posts nothing', () {
    test('discard from the app', () async {
      final c = container();
      final controller = await started(c, WorkoutType.running);
      second(bpm: 140, speed: 3);

      await controller.discard();
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.discarded);
      expect(notifier.endedNotices, isEmpty);
    });

    test('discard during the end question', () async {
      final controller = await started(container(), WorkoutType.other);
      second(bpm: 140);
      notifier.tap(WorkoutNoticeAction.stop);
      await pumpEventQueue();

      await controller.discard();
      notifier.tap(WorkoutNoticeAction.save);
      await pumpEventQueue();

      expect(notifier.endedNotices, isEmpty);
    });
  });
}
