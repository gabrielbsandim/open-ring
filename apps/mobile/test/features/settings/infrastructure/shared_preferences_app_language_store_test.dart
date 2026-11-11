import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/settings/domain/app_language.dart';
import 'package:open_ring/features/settings/infrastructure/shared_preferences_app_language_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('nothing saved reads as no choice', () async {
    final store = await SharedPreferencesAppLanguageStore.open();

    expect(store.read(), isNull);
  });

  test('a saved language survives reopening', () async {
    final first = await SharedPreferencesAppLanguageStore.open();
    await first.write(AppLanguage.portuguesePortugal);

    final second = await SharedPreferencesAppLanguageStore.open();

    expect(second.read(), AppLanguage.portuguesePortugal);
  });

  test('an unknown stored value reads as no choice', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          SharedPreferencesAppLanguageStore.key: 'klingon',
        });

    final store = await SharedPreferencesAppLanguageStore.open();

    expect(store.read(), isNull);
  });
}
