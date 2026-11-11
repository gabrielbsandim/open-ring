import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/infrastructure/shared_preferences_sync_interval_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('reads nothing before the first write', () async {
    final store = await SharedPreferencesSyncIntervalStore.open();

    expect(store.read(), isNull);
  });

  test('a written interval survives reopening', () async {
    final first = await SharedPreferencesSyncIntervalStore.open();
    await first.write(SyncInterval.minutes30);

    final second = await SharedPreferencesSyncIntervalStore.open();

    expect(second.read(), SyncInterval.minutes30);
  });

  test(
    'a stored value outside the offered intervals reads as nothing',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            SharedPreferencesSyncIntervalStore.key: 45,
          });

      final store = await SharedPreferencesSyncIntervalStore.open();

      expect(store.read(), isNull);
    },
  );
}
