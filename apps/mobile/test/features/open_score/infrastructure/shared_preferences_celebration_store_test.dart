import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/open_score/infrastructure/shared_preferences_celebration_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('the key is open_score_celebration_closed', () {
    expect(
      SharedPreferencesCelebrationStore.key,
      'open_score_celebration_closed',
    );
  });

  test('nothing is stored before a card is closed', () async {
    expect(await SharedPreferencesCelebrationStore().read(), isNull);
  });

  test('a closed day survives a new store instance', () async {
    await SharedPreferencesCelebrationStore().write('2026-11-15');

    expect(await SharedPreferencesCelebrationStore().read(), '2026-11-15');
  });
}
