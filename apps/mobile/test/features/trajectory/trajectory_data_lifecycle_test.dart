import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart' show LocalDate;
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/settings/infrastructure/device_local_data_eraser.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';
import 'package:open_ring/features/trajectory/infrastructure/drift_projection_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../helpers/ai_fakes.dart';
import '../../helpers/database.dart';

TrajectoryProjection _projection(LocalDate monday) => TrajectoryProjection(
  monday: monday,
  trendKg: 80.4,
  rateKgPerWeek: -0.5,
  lowKg: 78,
  midKg: 78.5,
  highKg: 79.2,
  createdAt: DateTime.utc(2026, 11, 23, 6),
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('Delete all data empties trajectory_projections', () async {
    final db = await pairedDatabase();
    final store = DriftProjectionStore(db);
    await store.insertIfAbsent(_projection(const LocalDate(2026, 11, 16)));
    await store.insertIfAbsent(_projection(const LocalDate(2026, 11, 23)));
    expect(await rowCount(db, 'trajectory_projections'), 2);

    await DeviceLocalDataEraser(
      db,
      InMemoryPhotoStore(),
      secrets: InMemorySecretStore(),
    ).eraseAll();

    expect(await rowCount(db, 'trajectory_projections'), 0);
    expect(await store.all(), isEmpty);
  });
}
