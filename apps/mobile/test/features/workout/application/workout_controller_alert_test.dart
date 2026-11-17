import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/workout/application/workout_alert_providers.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_state.dart';
import 'package:open_ring/features/workout/domain/live_heart_rate_source.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_alert_preferences.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/workout_fakes.dart';

const _englishAlert = WorkoutAlert(
  title: 'The ring stopped sending heart rate',
  text: 'The workout is still recording. Tap to reconnect.',
);

const _portugueseAlert = WorkoutAlert(
  title: 'O anel parou de enviar a FC',
  text: 'O treino continua sendo gravado. Toque para reconectar.',
  channel: 'Avisos do treino',
  reconnect: 'Reconectar',
);

final class ThrowingAlertNotifier implements WorkoutNotifier {
  final shown = <WorkoutNotice>[];
  final _actions = StreamController<WorkoutNoticeAction>.broadcast(sync: true);
  int alertCalls = 0;
  int clearCalls = 0;
  int hides = 0;

  @override
  Stream<WorkoutNoticeAction> get actions => _actions.stream;

  @override
  Future<void> show(WorkoutNotice notice) async => shown.add(notice);

  @override
  Future<void> hide() async => hides++;

  // Throws before returning a future, the harder case for the controller.
  @override
  Future<void> alert(WorkoutAlert alert) {
    alertCalls++;
    throw const WorkoutNotifierFailure();
  }

  @override
  Future<void> clearAlert() {
    clearCalls++;
    throw const WorkoutNotifierFailure();
  }
}

void main() {
  late FakeClock clock;
  late StreamController<void> ticks;
  late FakeHeartRateSource heartRate;
  late FakeLocationSource location;
  late InMemoryWorkoutNotifier notifier;
  late InMemoryWorkoutAlertPreferences preferences;
  late RecordingWorkoutStore store;

  setUp(() {
    clock = FakeClock(workoutStart);
    ticks = StreamController<void>.broadcast(sync: true);
    heartRate = FakeHeartRateSource();
    location = FakeLocationSource();
    notifier = InMemoryWorkoutNotifier();
    preferences = InMemoryWorkoutAlertPreferences();
    store = RecordingWorkoutStore();
  });

  tearDown(() => ticks.close());

  ProviderContainer container({WorkoutNotifier? withNotifier}) {
    final c = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock.call),
        workoutTicksProvider.overrideWithValue(() => ticks.stream),
        liveHeartRateSourceProvider.overrideWithValue(heartRate),
        locationSourceProvider.overrideWithValue(location),
        workoutStoreProvider.overrideWithValue(store),
        workoutNotifierProvider.overrideWithValue(withNotifier ?? notifier),
        workoutAlertPreferencesProvider.overrideWithValue(preferences),
        userProfileStoreProvider.overrideWithValue(
          InMemoryUserProfileStore(
            const UserProfile(birthYear: 1996, weightKilograms: 70),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  void second({int? bpm}) {
    clock.advance(const Duration(seconds: 1));
    if (bpm != null) heartRate.emit(bpm);
    ticks.add(null);
  }

  Future<void> silent(int seconds) async {
    for (var i = 0; i < seconds; i++) {
      second();
    }
    await pumpEventQueue();
  }

  Future<void> beat(int bpm) async {
    second(bpm: bpm);
    await pumpEventQueue();
  }

  Future<WorkoutController> started(
    ProviderContainer c, {
    LocationNotice notice = testNotice,
  }) async {
    final controller = c.read(workoutProvider.notifier);
    await controller.start(WorkoutType.other, notice: notice);
    return controller;
  }

  group('1: a stall of 30 s sends exactly one alert', () {
    test('29 silent seconds after a beat send nothing', () async {
      await started(container());
      await beat(140);

      await silent(29);

      expect(notifier.alerts, isEmpty);
    });

    test('the 30th silent second sends one alert', () async {
      final c = container();
      await started(c);
      await beat(140);
      await silent(29);

      await silent(1);

      expect(c.read(workoutProvider).heartRateStalled, isTrue);
      expect(notifier.alerts, hasLength(1));
    });

    test('more ticks while stalled send no second alert', () async {
      await started(container());
      await beat(140);
      await silent(30);

      await silent(120);

      expect(notifier.alerts, hasLength(1));
      expect(notifier.alertClears, 0);
    });

    test('the default labels give the English alert', () async {
      await started(container());
      await beat(140);

      await silent(30);

      expect(notifier.alerts.single, _englishAlert);
      expect(notifier.alerts.single.channel, 'Workout alerts');
      expect(notifier.alerts.single.reconnect, 'Reconnect');
    });

    test('the alert carries the labels the workout started with', () async {
      await started(
        container(),
        notice: const LocationNotice(
          title: 'Treino',
          text: 'Gravando',
          channel: 'Treino',
          live: WorkoutNoticeLabels(
            alertChannel: 'Avisos do treino',
            ringLostAlertTitle: 'O anel parou de enviar a FC',
            ringLostAlertText:
                'O treino continua sendo gravado. Toque para reconectar.',
            reconnect: 'Reconectar',
          ),
        ),
      );
      await beat(140);

      await silent(30);

      expect(notifier.alerts.single, _portugueseAlert);
    });

    test('a Portuguese workout notice gives the localized alert', () async {
      final pt = lookupAppLocalizations(const Locale('pt'));
      await started(container(), notice: workoutLocationNotice(pt));
      await beat(140);

      await silent(30);

      expect(notifier.alerts.single, _portugueseAlert);
    });

    test('a ring silent from the start alerts at 30 s', () async {
      await started(container());

      await silent(29);
      expect(notifier.alerts, isEmpty);

      await silent(1);
      expect(notifier.alerts, hasLength(1));
    });

    test('a beat out of range does not hold off the stall', () async {
      await started(container());
      await beat(140);
      await silent(10);

      await beat(minWorkoutHeartRate - 1);
      await silent(19);

      expect(notifier.alerts, hasLength(1));
    });
  });

  group('2: a valid beat clears the alert, a new stall alerts again', () {
    test('a valid beat after the alert clears it once', () async {
      final c = container();
      await started(c);
      await beat(140);
      await silent(30);

      await beat(142);
      await beat(143);
      await beat(144);

      expect(c.read(workoutProvider).heartRateStalled, isFalse);
      expect(notifier.alertClears, 1);
      expect(notifier.alerts, hasLength(1));
    });

    test('a reconnect during the loss clears the alert once', () async {
      final c = container();
      await started(c);
      await beat(140);
      await silent(30);

      await c.read(workoutProvider.notifier).reconnectHeartRate();
      await beat(142);

      expect(notifier.alertClears, 1);
      expect(notifier.alerts, hasLength(1));
    });

    test('a beat out of range does not clear it', () async {
      await started(container());
      await beat(140);
      await silent(30);

      await beat(maxWorkoutHeartRate + 1);
      await beat(0);

      expect(notifier.alertClears, 0);
    });

    test(
      'a second stall after the heart rate came back alerts again',
      () async {
        await started(container());
        await beat(140);
        await silent(30);
        await beat(142);

        await silent(29);
        expect(notifier.alerts, hasLength(1));

        await silent(1);
        expect(notifier.alerts, [_englishAlert, _englishAlert]);
        expect(notifier.alertClears, 1);
      },
    );

    test('a valid beat with no alert sent clears nothing', () async {
      await started(container());
      await beat(140);
      await silent(20);

      await beat(141);

      expect(notifier.alertClears, 0);
    });
  });

  group('3: with the preference false no alert is sent', () {
    test('a stall sends no alert and the notice still shows it', () async {
      await preferences.setAlertRingLost(alert: false);
      final c = container();
      await started(c);
      await beat(140);

      await silent(32);

      expect(c.read(workoutProvider).heartRateStalled, isTrue);
      expect(notifier.alerts, isEmpty);
      expect(notifier.shown.last.ringLost, isTrue);
    });

    test('the heart rate coming back clears nothing', () async {
      await preferences.setAlertRingLost(alert: false);
      await started(container());
      await beat(140);
      await silent(30);

      await beat(141);

      expect(notifier.alertClears, 0);
    });

    test('a running workout picks up the switch turned off', () async {
      final c = container();
      await started(c);
      await beat(140);

      await c.read(workoutRingLostAlertProvider.notifier).set(alert: false);
      await silent(30);

      expect(c.read(workoutProvider).heartRateStalled, isTrue);
      expect(notifier.alerts, isEmpty);
    });

    test('a running workout picks up the switch turned on', () async {
      await preferences.setAlertRingLost(alert: false);
      final c = container();
      await started(c);
      await beat(140);

      await c.read(workoutRingLostAlertProvider.notifier).set(alert: true);
      await silent(30);

      expect(notifier.alerts, [_englishAlert]);
    });
  });

  group('4: no alert while paused or with no ring', () {
    test('a paused workout never alerts', () async {
      final c = container();
      final controller = await started(c);
      await beat(140);

      controller.pause();
      await silent(90);

      expect(c.read(workoutProvider).status, WorkoutStatus.paused);
      expect(notifier.alerts, isEmpty);
    });

    test('resuming waits a full 30 s again before alerting', () async {
      final controller = await started(container());
      await beat(140);
      controller.pause();
      await silent(90);

      controller.resume();
      await silent(29);
      expect(notifier.alerts, isEmpty);

      await silent(1);
      expect(notifier.alerts, hasLength(1));
    });

    test('a workout started with no ring sends none', () async {
      final c = container();
      await started(c);
      heartRate.fail(const HeartRateUnavailable(HeartRateProblem.noRing));
      await pumpEventQueue();

      await silent(90);

      expect(c.read(workoutProvider).heartRateProblem, HeartRateProblem.noRing);
      expect(notifier.alerts, isEmpty);
      expect(notifier.alertClears, 0);
    });

    test('a heart rate stream that ends sends none', () async {
      await started(container());
      heartRate.close();
      await pumpEventQueue();

      await silent(90);

      expect(notifier.alerts, isEmpty);
    });
  });

  group('5: ending the workout or a ring problem after the alert', () {
    test('finishing after an alert hides the notice', () async {
      final c = container();
      final controller = await started(c);
      await beat(140);
      await silent(30);

      await controller.finish();
      await pumpEventQueue();

      expect(c.read(workoutProvider).status, WorkoutStatus.finished);
      expect(notifier.hides, 1);
      expect(notifier.alerts, hasLength(1));
    });

    test('discarding after an alert hides the notice', () async {
      final controller = await started(container());
      await beat(140);
      await silent(30);

      await controller.discard();
      await pumpEventQueue();

      expect(notifier.hides, 1);
      expect(notifier.alerts, hasLength(1));
    });

    test('no alert follows the end of the workout', () async {
      final controller = await started(container());
      await beat(140);
      await silent(20);

      await controller.finish();
      await silent(60);

      expect(notifier.alerts, isEmpty);
    });

    test('a ring problem that replaces the stall clears the alert', () async {
      final c = container();
      await started(c);
      await beat(140);
      await silent(30);

      heartRate.fail(const HeartRateUnavailable(HeartRateProblem.unreachable));
      await pumpEventQueue();
      await silent(5);

      expect(c.read(workoutProvider).heartRateStalled, isFalse);
      expect(notifier.alertClears, 1);
      expect(notifier.alerts, hasLength(1));
    });

    test('a ring problem with no alert sent clears nothing', () async {
      await started(container());
      await beat(140);
      await silent(10);

      heartRate.fail(const HeartRateUnavailable(HeartRateProblem.busy));
      await pumpEventQueue();

      expect(notifier.alertClears, 0);
    });
  });

  group('6: a notifier that throws does not stop the workout', () {
    test('a failing in-memory notifier is survived', () async {
      notifier.failing = true;
      final c = container();
      final controller = await started(c);
      await beat(140);
      await silent(30);
      await beat(141);
      await silent(30);

      await controller.finish();
      await pumpEventQueue();

      final state = c.read(workoutProvider);
      expect(state.status, WorkoutStatus.finished);
      expect(state.save, WorkoutSave.saved);
      expect(state.snapshot!.elapsed, const Duration(seconds: 62));
      expect(store.saved, hasLength(1));
    });

    test('alert and clearAlert that throw at once are survived', () async {
      final throwing = ThrowingAlertNotifier();
      final c = container(withNotifier: throwing);
      final controller = await started(c);
      await beat(140);
      await silent(32);
      expect(throwing.alertCalls, 1);
      expect(throwing.shown.last.ringLost, isTrue);

      await beat(141);
      await beat(142);
      expect(c.read(workoutProvider).heartRateStalled, isFalse);

      await silent(30);
      expect(throwing.alertCalls, 2);

      await controller.finish();
      await pumpEventQueue();

      expect(c.read(workoutProvider).save, WorkoutSave.saved);
      expect(throwing.hides, 1);
      expect(store.saved, hasLength(1));
    });

    test('a ring problem after a throwing alert is survived', () async {
      final throwing = ThrowingAlertNotifier();
      final c = container(withNotifier: throwing);
      await started(c);
      await beat(140);
      await silent(30);

      heartRate.fail(const HeartRateUnavailable(HeartRateProblem.unreachable));
      await pumpEventQueue();
      await silent(3);

      final state = c.read(workoutProvider);
      expect(state.status, WorkoutStatus.running);
      expect(state.heartRateProblem, HeartRateProblem.unreachable);
      expect(state.snapshot!.elapsed, const Duration(seconds: 34));
    });
  });
}
