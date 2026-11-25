import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/domain/food_energy_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/infrastructure/shared_preferences_food_energy_store.dart';
import 'package:open_ring/features/settings/infrastructure/device_local_data_eraser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/database.dart';

const FoodEnergyOptIn _optIn = (
  on: LocalDate(2026, 11, 24),
  soft: (id: 3, on: LocalDate(2026, 11, 3)),
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('the key is food_energy_opt_in', () {
    expect(SharedPreferencesFoodEnergyStore.key, 'food_energy_opt_in');
  });

  test('reads null when nothing is stored', () async {
    expect(await SharedPreferencesFoodEnergyStore().read(), isNull);
  });

  test('round trips across instances as the JSON the spec names', () async {
    await SharedPreferencesFoodEnergyStore().write(_optIn);

    expect(await SharedPreferencesFoodEnergyStore().read(), _optIn);
    expect(
      await SharedPreferencesAsync().getString('food_energy_opt_in'),
      '{"on":"2026-11-24","soft":{"id":3,"on":"2026-11-03"}}',
    );
  });

  test('an opt in with no soft screening round trips', () async {
    const none = (on: LocalDate(2026, 11, 24), soft: null);
    await SharedPreferencesFoodEnergyStore().write(none);

    expect(await SharedPreferencesFoodEnergyStore().read(), none);
  });

  test('clear removes the key', () async {
    final store = SharedPreferencesFoodEnergyStore();
    await store.write(_optIn);

    await store.clear();

    expect(await store.read(), isNull);
    expect(await SharedPreferencesAsync().getKeys(), isEmpty);
  });

  for (final raw in [
    'not json',
    '[]',
    '{"on":"2026-11-24"}',
    '{"on":"2026-11-24","soft_seen":0}',
    '{"on":"2026-02-30","soft":null}',
    '{"on":20261124,"soft":null}',
    '{"on":"2026-11-24","soft":5}',
    '{"on":"2026-11-24","soft":{"id":3}}',
    '{"on":"2026-11-24","soft":{"id":"3","on":"2026-11-03"}}',
  ]) {
    test('a corrupt value reads as null: $raw', () async {
      await SharedPreferencesAsync().setString('food_energy_opt_in', raw);

      expect(await SharedPreferencesFoodEnergyStore().read(), isNull);
    });
  }

  test('Delete all data removes food_energy_opt_in', () async {
    expect(
      DeviceLocalDataEraser.preferenceKeys,
      contains(SharedPreferencesFoodEnergyStore.key),
    );
    await SharedPreferencesFoodEnergyStore().write(_optIn);

    await DeviceLocalDataEraser(
      memoryDatabase(),
      InMemoryPhotoStore(),
      secrets: InMemorySecretStore(),
    ).eraseAll();

    expect(
      await SharedPreferencesAsync().getKeys(),
      isNot(contains('food_energy_opt_in')),
    );
    expect(await SharedPreferencesFoodEnergyStore().read(), isNull);
  });

  test('the in-memory store keeps what was written until cleared', () async {
    final store = InMemoryFoodEnergyStore();

    await store.write(_optIn);
    expect(await store.read(), _optIn);

    await store.clear();
    expect(await store.read(), isNull);
  });
}
