import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/settings/infrastructure/device_local_data_eraser.dart';
import 'package:open_ring/features/workout/application/workout_alert_providers.dart';
import 'package:open_ring/features/workout/domain/workout_alert_preferences.dart';
import 'package:open_ring/features/workout/infrastructure/shared_preferences_workout_alert_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/database.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('8: the stored preference', () {
    test('the key is workout_ring_lost_alert', () {
      expect(
        SharedPreferencesWorkoutAlertPreferences.key,
        'workout_ring_lost_alert',
      );
    });

    test('reads true when nothing is stored', () async {
      expect(
        await SharedPreferencesWorkoutAlertPreferences().alertRingLost(),
        isTrue,
      );
    });

    test('round trips false and back across instances', () async {
      await SharedPreferencesWorkoutAlertPreferences().setAlertRingLost(
        alert: false,
      );

      expect(
        await SharedPreferencesWorkoutAlertPreferences().alertRingLost(),
        isFalse,
      );

      await SharedPreferencesWorkoutAlertPreferences().setAlertRingLost(
        alert: true,
      );

      expect(
        await SharedPreferencesWorkoutAlertPreferences().alertRingLost(),
        isTrue,
      );
    });

    test('the key is stored as a bool under that name', () async {
      await SharedPreferencesWorkoutAlertPreferences().setAlertRingLost(
        alert: false,
      );

      expect(
        await SharedPreferencesAsync().getBool('workout_ring_lost_alert'),
        isFalse,
      );
    });

    test('does not share a key with the lock screen preference', () async {
      await SharedPreferencesWorkoutAlertPreferences().setAlertRingLost(
        alert: false,
      );

      expect(await SharedPreferencesAsync().getKeys(), {
        'workout_ring_lost_alert',
      });
    });
  });

  group('8: Delete all data', () {
    test('the key is in preferenceKeys', () {
      expect(
        DeviceLocalDataEraser.preferenceKeys,
        contains(SharedPreferencesWorkoutAlertPreferences.key),
      );
    });

    test('erasing turns the ring lost alert back on', () async {
      await SharedPreferencesWorkoutAlertPreferences().setAlertRingLost(
        alert: false,
      );

      await DeviceLocalDataEraser(
        memoryDatabase(),
        InMemoryPhotoStore(),
      ).eraseAll();

      expect(
        await SharedPreferencesAsync().getKeys(),
        isNot(contains('workout_ring_lost_alert')),
      );
      expect(
        await SharedPreferencesWorkoutAlertPreferences().alertRingLost(),
        isTrue,
      );
    });
  });

  group('the in-memory preference', () {
    test('defaults to alerting', () async {
      expect(await InMemoryWorkoutAlertPreferences().alertRingLost(), isTrue);
    });

    test('keeps what was set', () async {
      final preferences = InMemoryWorkoutAlertPreferences();

      await preferences.setAlertRingLost(alert: false);

      expect(await preferences.alertRingLost(), isFalse);
    });
  });

  group('the providers', () {
    ProviderContainer container(WorkoutAlertPreferences preferences) {
      final c = ProviderContainer(
        overrides: [
          workoutAlertPreferencesProvider.overrideWithValue(preferences),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the default provider is the in-memory one', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      expect(
        c.read(workoutAlertPreferencesProvider),
        isA<InMemoryWorkoutAlertPreferences>(),
      );
    });

    test('the controller loads true by default', () async {
      final c = container(InMemoryWorkoutAlertPreferences());

      expect(await c.read(workoutRingLostAlertProvider.future), isTrue);
    });

    test('the controller loads a stored false', () async {
      final preferences = InMemoryWorkoutAlertPreferences();
      await preferences.setAlertRingLost(alert: false);
      final c = container(preferences);

      expect(await c.read(workoutRingLostAlertProvider.future), isFalse);
    });

    test('set updates the state and stores the value', () async {
      final preferences = InMemoryWorkoutAlertPreferences();
      final c = container(preferences);
      await c.read(workoutRingLostAlertProvider.future);

      await c.read(workoutRingLostAlertProvider.notifier).set(alert: false);

      expect(c.read(workoutRingLostAlertProvider).value, isFalse);
      expect(await preferences.alertRingLost(), isFalse);
    });
  });
}
