import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/infrastructure/export_pages_dao.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';

final _from = DateTime.utc(2026, 11, 10);
final _to = DateTime.utc(2026, 11, 11);

int _ms(DateTime at) => at.millisecondsSinceEpoch;

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await pairedDatabase();
  });

  Future<void> session(
    String recordId,
    DateTime start, {
    String source = 'com.garmin.android.apps.connectmobile',
    int offsetMinutes = 0,
  }) => db
      .into(db.importedSleepSessions)
      .insert(
        ImportedSleepSessionsCompanion.insert(
          recordId: recordId,
          source: source,
          startUtcMs: _ms(start),
          endUtcMs: _ms(start.add(const Duration(hours: 8))),
          offsetMinutes: offsetMinutes,
          importedAtUtcMs: _ms(DateTime.utc(2026, 11, 12)),
        ),
      );

  Future<void> stage(
    String recordId,
    DateTime start, {
    Duration length = const Duration(minutes: 30),
    SleepStage kind = SleepStage.light,
  }) => db
      .into(db.importedSleepStages)
      .insert(
        ImportedSleepStagesCompanion.insert(
          recordId: recordId,
          startUtcMs: _ms(start),
          endUtcMs: _ms(start.add(length)),
          stage: kind,
        ),
      );

  Future<List<ImportedSleepStageRecord>> exported({int pageSize = 500}) async {
    final pages = await ExportPagesDao(
      db,
      pageSize: pageSize,
    ).pages(ExportKind.importedSleep, from: _from, to: _to).toList();
    return [for (final page in pages) ...page.cast<ImportedSleepStageRecord>()];
  }

  test('the kind is appended last with its columns', () {
    expect(ExportKind.values.last, ExportKind.importedSleep);
    expect(ExportKind.importedSleep.key, 'imported_sleep');
    expect(ExportKind.importedSleep.columns, [
      'session_start',
      'start',
      'end',
      'record_id',
      'source',
      'stage',
      'duration_s',
    ]);
  });

  test(
    'a session with three stages yields three rows with its offset',
    () async {
      final start = DateTime.utc(2026, 11, 10, 1);
      await session('night', start, offsetMinutes: -180);
      await stage('night', start);
      await stage(
        'night',
        start.add(const Duration(minutes: 30)),
        length: const Duration(minutes: 42, seconds: 30, milliseconds: 900),
        kind: SleepStage.deep,
      );
      await stage(
        'night',
        start.add(const Duration(hours: 2)),
        kind: SleepStage.rem,
      );

      final records = await exported();

      expect(records, hasLength(3));
      expect(records.map((r) => r.stage), [
        SleepStage.light,
        SleepStage.deep,
        SleepStage.rem,
      ]);
      expect({for (final r in records) r.sessionStart.utcMs}, {_ms(start)});
      for (final r in records) {
        expect(r.sessionStart.offsetMinutes, -180);
        expect(r.start.offsetMinutes, -180);
        expect(r.end.offsetMinutes, -180);
        expect(r.values.length, ExportKind.importedSleep.columns.length);
      }
      expect(records[1].values[5], 'deep');
      expect(records[1].values[6], 2550);
    },
  );

  test('a session that starts before from is out with stages inside', () async {
    final start = _from.subtract(const Duration(hours: 2));
    await session('before', start);
    await stage('before', _from.add(const Duration(hours: 1)));
    await stage('before', _from.add(const Duration(hours: 2)));

    expect(await exported(), isEmpty);
  });

  test('a session that starts at to is out', () async {
    await session('at-to', _to);
    await stage('at-to', _to);

    expect(await exported(), isEmpty);
  });

  test('a session that starts at from is in', () async {
    await session('at-from', _from);
    await stage('at-from', _from);

    expect((await exported()).map((r) => r.recordId), ['at-from']);
  });

  test('a session that starts inside is whole when stages pass to', () async {
    final start = DateTime.utc(2026, 11, 10, 22);
    await session('late', start);
    await stage('late', start);
    await stage('late', start.add(const Duration(hours: 3)));
    await stage('late', start.add(const Duration(hours: 6)));

    final records = await exported();

    expect(records, hasLength(3));
    expect(records.last.start.utcMs, greaterThan(_ms(_to)));
  });

  test(
    'stages tied on the start are split by record id across pages',
    () async {
      final start = DateTime.utc(2026, 11, 10, 1);
      for (final id in ['c', 'a', 'b']) {
        await session(id, start);
        await stage(id, start);
      }

      final pages = await ExportPagesDao(
        db,
        pageSize: 2,
      ).pages(ExportKind.importedSleep, from: _from, to: _to).toList();

      expect(pages.map((p) => p.length), [2, 1]);
      expect(
        [
          for (final page in pages)
            for (final r in page.cast<ImportedSleepStageRecord>()) r.recordId,
        ],
        ['a', 'b', 'c'],
      );
    },
  );

  test('five stages of two sessions with equal starts page cleanly', () async {
    final start = DateTime.utc(2026, 11, 10, 1);
    final later = start.add(const Duration(hours: 1));
    await session('b', start);
    await session('a', start);
    await stage('b', start);
    await stage('b', later);
    await stage('a', start);
    await stage('a', later);
    await stage('a', later.add(const Duration(hours: 1)));

    final pages = await ExportPagesDao(
      db,
      pageSize: 2,
    ).pages(ExportKind.importedSleep, from: _from, to: _to).toList();

    expect(pages.map((p) => p.length), [2, 2, 1]);
    expect(
      [
        for (final page in pages)
          for (final r in page.cast<ImportedSleepStageRecord>())
            (r.recordId, r.start.utcMs),
      ],
      [
        ('a', _ms(start)),
        ('b', _ms(start)),
        ('a', _ms(later)),
        ('b', _ms(later)),
        ('a', _ms(later.add(const Duration(hours: 1)))),
      ],
    );
  });

  test('a range that fills the last page exactly ends cleanly', () async {
    final start = DateTime.utc(2026, 11, 10, 1);
    await session('night', start);
    for (var hour = 0; hour < 4; hour++) {
      await stage('night', start.add(Duration(hours: hour)));
    }

    final pages = await ExportPagesDao(
      db,
      pageSize: 2,
    ).pages(ExportKind.importedSleep, from: _from, to: _to).toList();

    expect(pages.map((p) => p.length), [2, 2]);
  });

  test('an empty table yields no pages', () async {
    final pages = await ExportPagesDao(db)
        .pages(ExportKind.importedSleep, from: _from, to: _to)
        .toList();

    expect(pages, isEmpty);
  });

  test('a session with no stages yields no row and no error', () async {
    await session('empty', DateTime.utc(2026, 11, 10, 1));

    expect(await exported(), isEmpty);
  });

  test('rows are returned with reading switched off', () async {
    await db
        .into(db.healthReads)
        .insert(
          HealthReadsCompanion.insert(
            kind: HealthRecordKind.sleep,
            enabled: const Value(false),
          ),
        );
    final start = DateTime.utc(2026, 11, 10, 1);
    await session('kept', start);
    await stage('kept', start);

    expect((await exported()).map((r) => r.recordId), ['kept']);
  });

  test('rows from a lower priority source are returned', () async {
    await db
        .into(db.sourcePriorities)
        .insert(
          SourcePrioritiesCompanion.insert(
            metric: 'sleep',
            source: 'high',
            priority: 0,
          ),
        );
    final start = DateTime.utc(2026, 11, 10, 1);
    await session('high-night', start, source: 'high');
    await session('low-night', start, source: 'low');
    await stage('high-night', start);
    await stage('low-night', start);

    final records = await exported();

    expect(records.map((r) => r.recordId), ['high-night', 'low-night']);
    expect(records.map((r) => r.source), ['high', 'low']);
  });

  test('an awake only session is exported as stored', () async {
    final start = DateTime.utc(2026, 11, 10, 1);
    await session('awake', start);
    await stage('awake', start, kind: SleepStage.awake);

    final record = (await exported()).single;

    expect(record.stage, SleepStage.awake);
    expect(record.values[5], 'awake');
  });
}
