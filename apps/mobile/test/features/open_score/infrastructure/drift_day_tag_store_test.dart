import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/infrastructure/drift_day_tag_store.dart';

import '../../../helpers/database.dart';

const _date = LocalDate(2026, 11, 9);

void main() {
  test('a stored row lands in day_tags with the SQL column values', () async {
    final db = memoryDatabase();
    final store = DriftDayTagStore(db);

    await store.put(_date, DayTag.travel, now: DateTime.utc(2026, 11, 14, 12));

    final row = await db.customSelect('SELECT * FROM day_tags').getSingle();
    expect(row.read<String>('date'), '2026-11-09');
    expect(row.read<String>('tag'), 'travel');
    expect(
      row.read<int>('updated_at_utc_ms'),
      DateTime.utc(2026, 11, 14, 12).millisecondsSinceEpoch,
    );
  });

  test('an overwrite keeps one row and moves its timestamp', () async {
    final db = memoryDatabase();
    final store = DriftDayTagStore(db);
    await store.put(_date, DayTag.sick, now: DateTime.utc(2026, 11, 10));

    await store.put(_date, DayTag.rest, now: DateTime.utc(2026, 11, 12));

    final row = await db.customSelect('SELECT * FROM day_tags').getSingle();
    expect(row.read<String>('tag'), 'rest');
    expect(
      row.read<int>('updated_at_utc_ms'),
      DateTime.utc(2026, 11, 12).millisecondsSinceEpoch,
    );
  });

  test('a row with an unknown tag text is skipped', () async {
    final db = memoryDatabase();
    await db.customStatement(
      'INSERT INTO day_tags (date, tag, updated_at_utc_ms) '
      "VALUES ('2026-11-09', 'holiday', 1), ('2026-11-10', 'sick', 1)",
    );

    expect(await DriftDayTagStore(db).all(), {
      const LocalDate(2026, 11, 10): DayTag.sick,
    });
  });

  test('a row whose date text is not a date is skipped', () async {
    final db = memoryDatabase();
    await db.customStatement(
      'INSERT INTO day_tags (date, tag, updated_at_utc_ms) VALUES '
      "('not-a-date', 'sick', 1), ('2026-02-31', 'rest', 1), "
      "('2026-11-10', 'travel', 1)",
    );

    expect(await DriftDayTagStore(db).all(), {
      const LocalDate(2026, 11, 10): DayTag.travel,
    });
  });
}
