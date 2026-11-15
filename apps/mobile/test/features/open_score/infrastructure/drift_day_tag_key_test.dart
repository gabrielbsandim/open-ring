import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/infrastructure/drift_day_tag_store.dart';

import '../../../helpers/database.dart';

const _date = LocalDate(2026, 11, 14);

void main() {
  // The instants fall on the 13th, 14th and 15th in one zone or another, so
  // a key derived from the instant would move the tag to another day.
  for (final now in [
    DateTime.utc(2026, 11, 13, 13),
    DateTime.utc(2026, 11, 14, 12),
    DateTime.utc(2026, 11, 15, 11),
    DateTime(2026, 11, 15, 2),
  ]) {
    test('the key is the date text, whatever instant wrote it: $now', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final store = DriftDayTagStore(db);

      await store.put(_date, DayTag.travel, now: now);

      final row = await db
          .customSelect('SELECT date, updated_at_utc_ms FROM day_tags')
          .getSingle();
      expect(row.read<String>('date'), '2026-11-14');
      expect(row.read<int>('updated_at_utc_ms'), now.millisecondsSinceEpoch);
      expect(await store.all(), {_date: DayTag.travel});
    });
  }
}
