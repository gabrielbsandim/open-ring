import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/open_score/domain/celebration_store.dart';
import 'package:open_ring/features/open_score/domain/week_goal_store.dart';
import 'package:open_ring/features/open_score/infrastructure/shared_preferences_celebration_store.dart';
import 'package:open_ring/features/open_score/infrastructure/shared_preferences_week_goal_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  final goalStores = <String, WeekGoalStore Function()>{
    'InMemoryWeekGoalStore': InMemoryWeekGoalStore.new,
    'SharedPreferencesWeekGoalStore': SharedPreferencesWeekGoalStore.new,
  };
  for (final MapEntry(key: name, value: create) in goalStores.entries) {
    group('criterion 7: clear on $name', () {
      test('read is null after clearing a stored goal', () async {
        final store = create();
        await store.write(6);

        await store.clear();

        expect(await store.read(), isNull);
      });

      test('clear on an empty store is a no-op', () async {
        final store = create();

        await store.clear();

        expect(await store.read(), isNull);
      });

      test('a goal can be written again after a clear', () async {
        final store = create();
        await store.write(6);
        await store.clear();

        await store.write(2);

        expect(await store.read(), 2);
      });
    });
  }

  final celebrationStores = <String, CelebrationStore Function()>{
    'InMemoryCelebrationStore': InMemoryCelebrationStore.new,
    'SharedPreferencesCelebrationStore': SharedPreferencesCelebrationStore.new,
  };
  for (final MapEntry(key: name, value: create) in celebrationStores.entries) {
    group('criterion 7: clear on $name', () {
      test('read is null after clearing a closed day', () async {
        final store = create();
        await store.write('2026-11-15');

        await store.clear();

        expect(await store.read(), isNull);
      });

      test('clear on an empty store is a no-op', () async {
        final store = create();

        await store.clear();

        expect(await store.read(), isNull);
      });
    });
  }

  group('criterion 7: the preferences are removed, not blanked', () {
    test('the goal key is gone and other keys stay', () async {
      final preferences = SharedPreferencesAsync();
      await preferences.setString('unrelated', 'kept');
      await SharedPreferencesWeekGoalStore().write(6);

      await SharedPreferencesWeekGoalStore().clear();

      expect(
        await preferences.containsKey(SharedPreferencesWeekGoalStore.key),
        isFalse,
      );
      expect(await preferences.getString('unrelated'), 'kept');
    });

    test('the closed day key is gone and other keys stay', () async {
      final preferences = SharedPreferencesAsync();
      await preferences.setString('unrelated', 'kept');
      await SharedPreferencesCelebrationStore().write('2026-11-15');

      await SharedPreferencesCelebrationStore().clear();

      expect(
        await preferences.containsKey(SharedPreferencesCelebrationStore.key),
        isFalse,
      );
      expect(await preferences.getString('unrelated'), 'kept');
    });
  });
}
