import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/infrastructure/export_pages_dao.dart';

import '../../../helpers/database.dart';

final _from = DateTime.utc(2026, 11, 10);
final _to = DateTime.utc(2026, 11, 11);

int _ms(DateTime at) => at.millisecondsSinceEpoch;

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await pairedDatabase();
  });

  Future<void> imported(
    String recordId,
    DateTime start, {
    Duration length = const Duration(minutes: 30),
    String source = 'com.garmin.android.apps.connectmobile',
    String activityType = 'running',
    int offsetMinutes = 0,
    int? rating,
  }) => db
      .into(db.importedWorkouts)
      .insert(
        ImportedWorkoutsCompanion.insert(
          recordId: recordId,
          source: source,
          activityType: activityType,
          startUtcMs: _ms(start),
          endUtcMs: _ms(start.add(length)),
          offsetMinutes: offsetMinutes,
          importedAtUtcMs: _ms(DateTime.utc(2026, 11, 12)),
          effortRating: Value(rating),
        ),
      );

  Future<List<ImportedWorkoutRecord>> exported({int pageSize = 500}) async {
    final pages = await ExportPagesDao(
      db,
      pageSize: pageSize,
    ).pages(ExportKind.importedWorkouts, from: _from, to: _to).toList();
    return [for (final page in pages) ...page.cast<ImportedWorkoutRecord>()];
  }

  test('the kind is appended after day tags with its columns', () {
    expect(
      ExportKind.values[ExportKind.values.length - 2],
      ExportKind.importedWorkouts,
    );
    expect(ExportKind.importedWorkouts.key, 'imported_workouts');
    expect(ExportKind.importedWorkouts.columns, [
      'start',
      'end',
      'record_id',
      'source',
      'activity_type',
      'duration_s',
      'effort_rating',
    ]);
  });

  test('rows are selected by start in [from, to), ordered by start', () async {
    await imported('late', DateTime.utc(2026, 11, 10, 20));
    await imported('early', DateTime.utc(2026, 11, 10, 1));
    await imported('at-from', _from);
    await imported('at-to', _to);
    await imported('before', _from.subtract(const Duration(seconds: 1)));

    final records = await exported();

    expect(records.map((r) => r.recordId), ['at-from', 'early', 'late']);
  });

  test('a row that starts before the range and ends inside is out', () async {
    await imported(
      'crossing',
      _from.subtract(const Duration(minutes: 10)),
      length: const Duration(hours: 1),
    );

    expect(await exported(), isEmpty);
  });

  test('an empty table yields no pages', () async {
    final pages = await ExportPagesDao(db)
        .pages(ExportKind.importedWorkouts, from: _from, to: _to)
        .toList();

    expect(pages, isEmpty);
  });

  test('equal starts are paged by record id, none skipped', () async {
    final start = DateTime.utc(2026, 11, 10, 9);
    for (final id in ['c', 'a', 'e', 'b', 'd']) {
      await imported(id, start);
    }
    await imported('z-later', DateTime.utc(2026, 11, 10, 10));

    final pages = await ExportPagesDao(
      db,
      pageSize: 2,
    ).pages(ExportKind.importedWorkouts, from: _from, to: _to).toList();

    expect(pages.map((p) => p.length), [2, 2, 2]);
    expect(
      [
        for (final page in pages)
          for (final r in page.cast<ImportedWorkoutRecord>()) r.recordId,
      ],
      ['a', 'b', 'c', 'd', 'e', 'z-later'],
    );
  });

  test('a range that fills the last page exactly ends cleanly', () async {
    for (var hour = 0; hour < 4; hour++) {
      await imported('r$hour', DateTime.utc(2026, 11, 10, hour));
    }

    final pages = await ExportPagesDao(
      db,
      pageSize: 2,
    ).pages(ExportKind.importedWorkouts, from: _from, to: _to).toList();

    expect(pages.map((p) => p.length), [2, 2]);
  });

  test('rows are returned with reading switched off', () async {
    await db
        .into(db.healthReads)
        .insert(
          HealthReadsCompanion.insert(
            kind: HealthRecordKind.workout,
            enabled: const Value(false),
          ),
        );
    await imported('kept', DateTime.utc(2026, 11, 10, 8));

    expect((await exported()).map((r) => r.recordId), ['kept']);
  });

  test('rows hidden by overlap with a recorded workout are returned', () async {
    final start = DateTime.utc(2026, 11, 10, 8);
    await db
        .into(db.workouts)
        .insert(
          WorkoutsCompanion.insert(
            clientId: 'recorded',
            activityType: 'running',
            startUtcMs: _ms(start),
            endUtcMs: Value(_ms(start.add(const Duration(hours: 1)))),
            offsetMinutes: 0,
          ),
        );
    await imported('overlapped', start.add(const Duration(minutes: 5)));

    expect((await exported()).map((r) => r.recordId), ['overlapped']);
  });

  test('a record carries its stored fields and whole seconds', () async {
    await imported(
      'full',
      DateTime.utc(2026, 11, 10, 9),
      length: const Duration(minutes: 42, seconds: 30, milliseconds: 900),
      source: 'a,b',
      activityType: 'cycling',
      offsetMinutes: -180,
      rating: 7,
    );

    final record = (await exported()).single;

    expect(record.start.utcMs, _ms(DateTime.utc(2026, 11, 10, 9)));
    expect(record.start.offsetMinutes, -180);
    expect(record.end.offsetMinutes, -180);
    expect(record.source, 'a,b');
    expect(record.activityType, 'cycling');
    expect(record.values[5], 2550);
    expect(record.values.length, ExportKind.importedWorkouts.columns.length);
  });

  test('the rating is exported as stored, null and 11 included', () async {
    for (final (id, hour, rating) in [
      ('rated', 9, 7),
      ('above-scale', 10, 11),
      ('unrated', 11, null),
    ]) {
      await imported(id, DateTime.utc(2026, 11, 10, hour), rating: rating);
    }

    final records = await exported();

    expect(
      {for (final r in records) r.recordId: r.effortRating},
      {'rated': 7, 'above-scale': 11, 'unrated': null},
    );
    expect(records.map((r) => r.values.last), [7, 11, null]);
  });
}
