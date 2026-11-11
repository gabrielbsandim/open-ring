import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_read_store.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_imported_sleep_reader.dart';

import '../../../helpers/database.dart';
import '../../../helpers/fake_health_reader.dart';

void main() {
  const watch = 'com.garmin.android.apps.connectmobile';
  final lastNight = DateTime.utc(2026, 11, 9, 23);
  final from = DateTime.utc(2026, 11, 9);
  final to = DateTime.utc(2026, 11, 10, 12);

  Future<DriftHealthReadStore> seeded(DriftHealthReadStore store) async {
    await store.saveSleep([
      externalNight(watch, lastNight),
    ], readAt: DateTime.utc(2026, 11, 10, 9));
    return store;
  }

  test('with reading off it returns the ring alone', () async {
    final db = memoryDatabase();
    await seeded(DriftHealthReadStore(db));

    final imported = await DriftImportedSleepReader(db)
        .importedSleep(from: from, to: to);

    expect(imported.priority, [ringSource]);
    expect(imported.spans, isEmpty);
  });

  test('with reading on it returns spans by source and the order', () async {
    final db = memoryDatabase();
    final store = await seeded(DriftHealthReadStore(db));
    await store.setEnabled(HealthRecordKind.sleep, enabled: true);

    final imported = await DriftImportedSleepReader(db)
        .importedSleep(from: from, to: to);

    expect(imported.priority, [ringSource, watch]);
    final spans = imported.spans[watch]!;
    expect(spans.map((s) => s.phase), [SleepPhase.light, SleepPhase.rem]);
    expect(spans.first.start, lastNight);
    expect(spans.last.end, lastNight.add(const Duration(hours: 7)));
  });

  test('leaves out stages outside the range', () async {
    final db = memoryDatabase();
    final store = await seeded(DriftHealthReadStore(db));
    await store.setEnabled(HealthRecordKind.sleep, enabled: true);

    final imported = await DriftImportedSleepReader(db)
        .importedSleep(from: DateTime.utc(2026, 11, 10, 8), to: to);

    expect(imported.spans, isEmpty);
  });
}
