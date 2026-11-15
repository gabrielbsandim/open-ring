import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/body/infrastructure/shared_preferences_hide_numbers_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('the key is body_hide_numbers', () {
    expect(SharedPreferencesHideNumbersStore.key, 'body_hide_numbers');
  });

  test('numbers show when nothing is stored', () async {
    expect(await SharedPreferencesHideNumbersStore().read(), isFalse);
  });

  test('a written choice survives a new store instance', () async {
    await SharedPreferencesHideNumbersStore().write(hidden: true);

    expect(await SharedPreferencesHideNumbersStore().read(), isTrue);

    await SharedPreferencesHideNumbersStore().write(hidden: false);

    expect(await SharedPreferencesHideNumbersStore().read(), isFalse);
  });
}
