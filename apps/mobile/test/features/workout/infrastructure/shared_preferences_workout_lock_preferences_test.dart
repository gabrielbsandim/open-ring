import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/settings/infrastructure/device_local_data_eraser.dart';
import 'package:open_ring/features/workout/application/workout_lock_providers.dart';
import 'package:open_ring/features/workout/domain/workout_lock_preferences.dart';
import 'package:open_ring/features/workout/infrastructure/shared_preferences_workout_lock_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/database.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('8: the stored preference', () {
    test('the key is workout_lock_heart_rate', () {
      expect(
        SharedPreferencesWorkoutLockPreferences.key,
        'workout_lock_heart_rate',
      );
    });

    test('reads true when nothing is stored', () async {
      expect(
        await SharedPreferencesWorkoutLockPreferences().showHeartRate(),
        isTrue,
      );
    });

    test('round trips false and back across instances', () async {
      await SharedPreferencesWorkoutLockPreferences().setShowHeartRate(
        show: false,
      );

      expect(
        await SharedPreferencesWorkoutLockPreferences().showHeartRate(),
        isFalse,
      );

      await SharedPreferencesWorkoutLockPreferences().setShowHeartRate(
        show: true,
      );

      expect(
        await SharedPreferencesWorkoutLockPreferences().showHeartRate(),
        isTrue,
      );
    });

    test('the key is stored as a bool under that name', () async {
      await SharedPreferencesWorkoutLockPreferences().setShowHeartRate(
        show: false,
      );

      expect(
        await SharedPreferencesAsync().getBool('workout_lock_heart_rate'),
        isFalse,
      );
    });
  });

  group('8: Delete all data', () {
    test('the key is in preferenceKeys', () {
      expect(
        DeviceLocalDataEraser.preferenceKeys,
        contains(SharedPreferencesWorkoutLockPreferences.key),
      );
    });

    test('erasing brings the heart rate back on the lock screen', () async {
      await SharedPreferencesWorkoutLockPreferences().setShowHeartRate(
        show: false,
      );

      await DeviceLocalDataEraser(
        memoryDatabase(),
        InMemoryPhotoStore(),
        secrets: InMemorySecretStore(),
      ).eraseAll();

      expect(
        await SharedPreferencesAsync().getKeys(),
        isNot(contains('workout_lock_heart_rate')),
      );
      expect(
        await SharedPreferencesWorkoutLockPreferences().showHeartRate(),
        isTrue,
      );
    });
  });

  group('the in-memory preference', () {
    test('defaults to showing the heart rate', () async {
      expect(await InMemoryWorkoutLockPreferences().showHeartRate(), isTrue);
    });

    test('keeps what was set', () async {
      final preferences = InMemoryWorkoutLockPreferences();

      await preferences.setShowHeartRate(show: false);

      expect(await preferences.showHeartRate(), isFalse);
    });
  });

  group('the providers', () {
    ProviderContainer container(WorkoutLockPreferences preferences) {
      final c = ProviderContainer(
        overrides: [
          workoutLockPreferencesProvider.overrideWithValue(preferences),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the default provider is the in-memory one', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      expect(
        c.read(workoutLockPreferencesProvider),
        isA<InMemoryWorkoutLockPreferences>(),
      );
    });

    test('the controller loads true by default', () async {
      final c = container(InMemoryWorkoutLockPreferences());

      expect(await c.read(workoutLockHeartRateProvider.future), isTrue);
    });

    test('set updates the state and stores the value', () async {
      final preferences = InMemoryWorkoutLockPreferences();
      final c = container(preferences);
      await c.read(workoutLockHeartRateProvider.future);

      await c.read(workoutLockHeartRateProvider.notifier).set(show: false);

      expect(c.read(workoutLockHeartRateProvider).value, isFalse);
      expect(await preferences.showHeartRate(), isFalse);
    });
  });
}
