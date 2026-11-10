import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/shared_preferences_theme_mode_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('reads nothing before the first write', () async {
    final store = await SharedPreferencesThemeModeStore.open();

    expect(store.read(), isNull);
  });

  test('a written mode survives reopening', () async {
    final first = await SharedPreferencesThemeModeStore.open();
    await first.write(ThemeMode.dark);

    final second = await SharedPreferencesThemeModeStore.open();

    expect(second.read(), ThemeMode.dark);
  });

  test('an unknown stored value reads as nothing', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          SharedPreferencesThemeModeStore.key: 'sepia',
        });

    final store = await SharedPreferencesThemeModeStore.open();

    expect(store.read(), isNull);
  });
}
