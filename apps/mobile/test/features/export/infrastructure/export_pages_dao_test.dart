import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/infrastructure/export_pages_dao.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';

const _otherRing = 'A00_0001';

final _from = DateTime.utc(2026, 11, 10);
final _to = DateTime.utc(2026, 11, 11);

int _ms(DateTime at) => at.millisecondsSinceEpoch;

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await pairedDatabase();
    await RingDevicesDao(db).pair(
      const RingIdentity(deviceId: _otherRing, name: _otherRing),
      at: DateTime.utc(2026, 10),
    );
  });

  Future<void> stress(String device, DateTime at, int level) => db
      .into(db.stressSamples)
      .insert(
        StressSamplesCompanion.insert(
          deviceId: device,
          atUtcMs: _ms(at),
          offsetMinutes: 0,
          level: level,
        ),
      );

  test('samples come in pages ordered by time, then device', () async {
    final noon = DateTime.utc(2026, 11, 10, 12);
    await stress(ringId, noon, 3);
    await stress(_otherRing, noon, 2);
    await stress(ringId, DateTime.utc(2026, 11, 10, 1), 1);
    await stress(_otherRing, DateTime.utc(2026, 11, 10, 13), 4);
    await stress(ringId, DateTime.utc(2026, 11, 10, 23, 59), 5);
    await stress(ringId, _to, 99);
    await stress(ringId, _from.subtract(const Duration(seconds: 1)), 98);

    final pages = await ExportPagesDao(
      db,
      pageSize: 2,
    ).pages(ExportKind.stress, from: _from, to: _to).toList();

    expect(pages.map((p) => p.length), [2, 2, 1]);
    expect(
      [
        for (final page in pages)
          for (final record in page.cast<SampleRecord>()) record.value,
      ],
      [1, 2, 3, 4, 5],
    );
  });

  test('a range that fills the last page exactly ends cleanly', () async {
    for (var hour = 0; hour < 4; hour++) {
      await stress(ringId, DateTime.utc(2026, 11, 10, hour), hour + 1);
    }

    final pages = await ExportPagesDao(
      db,
      pageSize: 2,
    ).pages(ExportKind.stress, from: _from, to: _to).toList();

    expect(pages.map((p) => p.length), [2, 2]);
  });

  test('an empty range yields no pages', () async {
    final pages = await ExportPagesDao(db)
        .pages(ExportKind.heartRate, from: _from, to: _to)
        .toList();

    expect(pages, isEmpty);
  });

  test('workouts with the same start are paged by id', () async {
    final start = DateTime.utc(2026, 11, 10, 9);
    for (final clientId in ['a', 'b', 'c']) {
      await db
          .into(db.workouts)
          .insert(
            WorkoutsCompanion.insert(
              clientId: clientId,
              activityType: 'walking',
              startUtcMs: _ms(start),
              offsetMinutes: 0,
              deviceId: const Value(ringId),
            ),
          );
    }

    final pages = await ExportPagesDao(
      db,
      pageSize: 2,
    ).pages(ExportKind.workouts, from: _from, to: _to).toList();

    expect(
      [
        for (final page in pages)
          for (final record in page.cast<WorkoutRecord>()) record.clientId,
      ],
      ['a', 'b', 'c'],
    );
  });

  test('the device is the most recently paired ring', () async {
    final device = await ExportPagesDao(db).latestDevice();

    expect(device?.id, ringId);
    expect(device?.model, 'R09');
  });
}
