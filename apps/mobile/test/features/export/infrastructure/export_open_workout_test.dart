import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/infrastructure/export_pages_dao.dart';

import '../../../helpers/database.dart';

final _from = DateTime.utc(2026, 11, 10);
final _to = DateTime.utc(2026, 11, 11);

int _ms(DateTime at) => at.millisecondsSinceEpoch;

void main() {
  test('the workouts export skips a workout that is still open', () async {
    final db = memoryDatabase();
    final morning = DateTime.utc(2026, 11, 10, 7);
    await db
        .into(db.workouts)
        .insert(
          WorkoutsCompanion.insert(
            clientId: 'finished',
            activityType: 'running',
            startUtcMs: _ms(morning),
            endUtcMs: Value(_ms(morning.add(const Duration(minutes: 30)))),
            offsetMinutes: 0,
          ),
        );
    await db
        .into(db.workouts)
        .insert(
          WorkoutsCompanion.insert(
            clientId: 'open',
            activityType: 'running',
            startUtcMs: _ms(morning.add(const Duration(hours: 2))),
            offsetMinutes: 0,
          ),
        );

    final pages = await ExportPagesDao(db)
        .pages(ExportKind.workouts, from: _from, to: _to)
        .toList();

    final records = [for (final page in pages) ...page.cast<WorkoutRecord>()];
    expect(records.map((r) => r.clientId), ['finished']);
    expect(records.single.end, isNotNull);
  });
}
