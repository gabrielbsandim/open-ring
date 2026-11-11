import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/infrastructure/shared_preferences_today_widget_config_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('a saved config survives reopening', () async {
    final first = await SharedPreferencesTodayWidgetConfigStore.open();
    await first.write(TodayWidgetConfig().withTheme(WidgetTheme.dark));

    final second = await SharedPreferencesTodayWidgetConfigStore.open();

    expect(second.read()?.theme, WidgetTheme.dark);
  });

  test('a reset config stays gone after reopening', () async {
    final first = await SharedPreferencesTodayWidgetConfigStore.open();
    await first.write(TodayWidgetConfig().withTheme(WidgetTheme.dark));
    await first.reset();

    expect(first.read(), isNull);
    final second = await SharedPreferencesTodayWidgetConfigStore.open();
    expect(second.read(), isNull);
  });
}
