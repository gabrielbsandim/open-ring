import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/settings/infrastructure/device_local_data_eraser.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/database.dart';

const _goal =
    'INSERT INTO goals (kind, started_on, block_started_on, phase, '
    'phase_since, levers) '
    "VALUES ('loseFat', '2026-11-16', '2026-11-16', 'block', '2026-11-16', "
    '\'{"v":1,"levers":[]}\')';

const _week =
    'INSERT INTO goal_weeks (goal_id, monday, inputs, rule, action) '
    "VALUES (1, '2026-12-07', '{}', 'build', 'nextStep')";

const _screening =
    'INSERT INTO goal_screenings (asked_on, soft_mode) '
    "VALUES ('2026-11-16', 0)";

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('the eraser empties goals, goal_weeks and goal_screenings', () async {
    final db = await pairedDatabase();
    await db.customStatement(_goal);
    await db.customStatement(_week);
    await db.customStatement(_screening);
    expect(await rowCount(db, 'goals'), 1);
    expect(await rowCount(db, 'goal_weeks'), 1);
    expect(await rowCount(db, 'goal_screenings'), 1);

    await DeviceLocalDataEraser(db, InMemoryPhotoStore()).eraseAll();

    expect(await rowCount(db, 'goals'), 0);
    expect(await rowCount(db, 'goal_weeks'), 0);
    expect(await rowCount(db, 'goal_screenings'), 0);
  });
}
