import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/settings/infrastructure/device_local_data_eraser.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/database.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('the eraser removes every step_goal_changes row', () async {
    final db = await pairedDatabase();
    await db.customStatement(
      'INSERT INTO step_goal_changes (effective_date, steps) '
      "VALUES ('1970-01-01', 8000), ('2026-12-07', 10000)",
    );
    expect(await rowCount(db, 'step_goal_changes'), 2);

    await DeviceLocalDataEraser(
      db,
      InMemoryPhotoStore(),
      secrets: InMemorySecretStore(),
    ).eraseAll();

    expect(await rowCount(db, 'step_goal_changes'), 0);
  });
}
