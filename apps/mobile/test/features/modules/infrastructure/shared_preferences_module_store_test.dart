import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/infrastructure/shared_preferences_module_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('the key is modules_enabled', () {
    expect(SharedPreferencesModuleStore.key, 'modules_enabled');
  });

  test('reads the empty set when nothing is stored', () async {
    expect(await SharedPreferencesModuleStore().read(), isEmpty);
  });

  test('a written set survives a new store instance', () async {
    await SharedPreferencesModuleStore().write({
      ModuleId.body,
      ModuleId.trajectory,
    });

    expect(await SharedPreferencesModuleStore().read(), {
      ModuleId.body,
      ModuleId.trajectory,
    });
  });

  test('writing the empty set reads back empty', () async {
    final store = SharedPreferencesModuleStore();
    await store.write({ModuleId.body});
    await store.write({});

    expect(await store.read(), isEmpty);
  });

  test('an unknown name or a duplicate in the stored list is dropped', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          SharedPreferencesModuleStore.key: ['body', 'nope', 'body', 'food'],
        });

    expect(await SharedPreferencesModuleStore().read(), {
      ModuleId.body,
      ModuleId.food,
    });
  });
}
