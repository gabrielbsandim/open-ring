import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/infrastructure/device_local_data_eraser.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/database.dart';

const _insert =
    'INSERT INTO day_tags (date, tag, updated_at_utc_ms) '
    "VALUES ('2026-11-09', 'sick', 1), ('2026-11-10', 'rest', 1)";

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('the eraser removes every day_tags row', () async {
    final db = await pairedDatabase();
    await db.customStatement(_insert);
    expect(await rowCount(db, 'day_tags'), 2);

    await DeviceLocalDataEraser(db).eraseAll();

    expect(await rowCount(db, 'day_tags'), 0);
  });

  test('turning the Open Score module off leaves the rows', () async {
    final db = await pairedDatabase();
    await db.customStatement(_insert);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        moduleStoreProvider.overrideWithValue(
          InMemoryModuleStore({ModuleId.openScore}),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(enabledModulesProvider.future);

    await container
        .read(enabledModulesProvider.notifier)
        .disable(ModuleId.openScore);

    expect(await container.read(enabledModulesProvider.future), isEmpty);
    expect(await rowCount(db, 'day_tags'), 2);
  });
}
