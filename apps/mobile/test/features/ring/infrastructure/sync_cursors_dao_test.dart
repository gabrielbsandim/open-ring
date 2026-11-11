import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:open_ring/features/ring/infrastructure/sync_cursors_dao.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';
import '../../../helpers/sync_fixtures.dart';

void main() {
  late AppDatabase db;
  late SyncCursorsDao dao;

  setUp(() async {
    db = await pairedDatabase();
    dao = SyncCursorsDao(db);
  });

  test('a ring without cursors has none', () async {
    expect(await dao.cursorsFor(ringId), isEmpty);
  });

  test('cursors are stored per kind and only move forward', () async {
    final earlier = syncNow.subtract(const Duration(hours: 1));
    await dao.advance(ringId, {
      RecordKind.heartRate: syncNow,
      RecordKind.sleep: nightStart,
    }, at: syncNow);

    await dao.advance(ringId, {
      RecordKind.heartRate: earlier,
      RecordKind.sleep: syncNow,
    }, at: syncNow);

    expect(await dao.cursorsFor(ringId), {
      RecordKind.heartRate: syncNow,
      RecordKind.sleep: syncNow,
    });
  });

  test('cursors of one ring do not leak into another', () async {
    await RingDevicesDao(db).pair(
      const RingIdentity(deviceId: 'R09_BEEF', name: 'R09_BEEF'),
      at: syncNow,
    );
    await dao.advance('R09_BEEF', {RecordKind.hrv: syncNow}, at: syncNow);

    expect(await dao.cursorsFor(ringId), isEmpty);
    expect(await dao.cursorsFor('R09_BEEF'), {RecordKind.hrv: syncNow});
  });
}
