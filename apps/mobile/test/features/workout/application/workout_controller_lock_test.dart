import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_lock_providers.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_lock_preferences.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/workout_fakes.dart';

void main() {
  late FakeClock clock;
  late StreamController<void> ticks;
  late FakeHeartRateSource heartRate;
  late FakeLocationSource location;
  late InMemoryWorkoutNotifier notifier;
  late InMemoryWorkoutLockPreferences preferences;

  setUp(() {
    clock = FakeClock(workoutStart);
    ticks = StreamController<void>.broadcast(sync: true);
    heartRate = FakeHeartRateSource();
    location = FakeLocationSource();
    notifier = InMemoryWorkoutNotifier();
    preferences = InMemoryWorkoutLockPreferences();
  });

  tearDown(() => ticks.close());

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock.call),
        workoutTicksProvider.overrideWithValue(() => ticks.stream),
        liveHeartRateSourceProvider.overrideWithValue(heartRate),
        locationSourceProvider.overrideWithValue(location),
        workoutStoreProvider.overrideWithValue(RecordingWorkoutStore()),
        workoutNotifierProvider.overrideWithValue(notifier),
        workoutLockPreferencesProvider.overrideWithValue(preferences),
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

  Future<void> started(ProviderContainer c) => c
      .read(workoutProvider.notifier)
      .start(WorkoutType.other, notice: testNotice);

  group('7: the controller posts the public version', () {
    test('with the default preference the first notice has none', () async {
      await started(container());

      expect(notifier.shown.first.publicTitle, isNull);
      expect(notifier.shown.first.publicText, isNull);
    });

    test('with the preference off the very first notice has them', () async {
      await preferences.setShowHeartRate(show: false);

      await started(container());

      final first = notifier.shown.first;
      expect(first.publicTitle, testNotice.title);
      expect(first.publicText, testNotice.live.recording);
    });

    test('a heart rate never reaches the public text', () async {
      await preferences.setShowHeartRate(show: false);
      await started(container());

      second(bpm: 150);
      second(bpm: 150);

      final last = notifier.shown.last;
      expect(last.text, contains('150'));
      expect(last.publicText, isNotNull);
      expect(last.publicText, isNot(contains('150')));
      expect(last.publicText, isNot(contains('bpm')));
    });

    test('a running workout picks up the switch turned off', () async {
      final c = container();
      await started(c);
      second(bpm: 120);
      expect(notifier.shown.last.publicText, isNull);

      await c.read(workoutLockHeartRateProvider.notifier).set(show: false);
      second(bpm: 121);
      second(bpm: 122);

      expect(notifier.shown.last.publicText, isNotNull);
      expect(notifier.shown.last.publicText, isNot(contains('bpm')));
    });

    test('a running workout picks up the switch turned back on', () async {
      await preferences.setShowHeartRate(show: false);
      final c = container();
      await started(c);
      second(bpm: 120);
      expect(notifier.shown.last.publicText, isNotNull);

      await c.read(workoutLockHeartRateProvider.notifier).set(show: true);
      second(bpm: 121);
      second(bpm: 122);

      expect(notifier.shown.last.publicTitle, isNull);
      expect(notifier.shown.last.publicText, isNull);
    });
  });
}
