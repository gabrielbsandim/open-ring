import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/infrastructure/shared_preferences_unit_system_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('nothing saved reads as no choice', () async {
    expect(await SharedPreferencesUnitSystemStore().read(), isNull);
  });

  test('a saved choice reads back in a new store', () async {
    await SharedPreferencesUnitSystemStore().write(UnitSystem.imperial);

    expect(
      await SharedPreferencesUnitSystemStore().read(),
      UnitSystem.imperial,
    );
  });

  test('an unknown stored value reads as no choice', () async {
    await SharedPreferencesAsync().setString(
      SharedPreferencesUnitSystemStore.key,
      'furlongs',
    );

    expect(await SharedPreferencesUnitSystemStore().read(), isNull);
  });

  test('imperial conversions round trip', () {
    expect(
      ImperialUnits.centimeters(ImperialUnits.inches(178)),
      closeTo(178, 1e-9),
    );
    expect(ImperialUnits.pounds(76.5), closeTo(168.65, 0.01));
  });
}
