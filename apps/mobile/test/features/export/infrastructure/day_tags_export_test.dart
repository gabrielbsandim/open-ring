import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/domain/export_request.dart';
import 'package:open_ring/features/export/infrastructure/drift_data_exporter.dart';
import 'package:open_ring/features/export/infrastructure/export_pages_dao.dart';

import '../../../helpers/database.dart';

final _now = DateTime.utc(2026, 11, 10, 15);
final _from = DateTime.utc(2026, 11, 3);
final _to = DateTime.utc(2026, 11, 11);

Future<void> _seed(AppDatabase db) => db.customStatement(
  'INSERT INTO day_tags (date, tag, updated_at_utc_ms) VALUES '
  "('2026-08-01', 'rest', 1), ('2026-11-09', 'travel', 1), "
  "('2026-11-05', 'sick', 1), ('2027-02-01', 'rest', 1)",
);

void main() {
  late AppDatabase db;
  late Directory root;
  late DriftDataExporter exporter;

  setUp(() async {
    db = await pairedDatabase(pairedAt: DateTime.utc(2026, 11));
    await _seed(db);
    root = Directory.systemTemp.createTempSync('openring_day_tags_test_');
    addTearDown(() => root.delete(recursive: true));
    exporter = DriftDataExporter(
      database: db,
      clock: () => _now,
      directory: () async => root,
    );
  });

  ExportRequest request(ExportFormat format) => ExportRequest(
    from: _from,
    to: _to,
    kinds: const [ExportKind.dayTags],
    format: format,
  );

  test('the kind is named day_tags with the date and tag columns', () {
    expect(ExportKind.dayTags.key, 'day_tags');
    expect(ExportKind.dayTags.columns, ['date', 'tag']);
  });

  test('the pages carry the dates in the range, oldest first', () async {
    final pages = await ExportPagesDao(db)
        .pages(ExportKind.dayTags, from: _from, to: _to)
        .toList();

    final records = [for (final page in pages) ...page.cast<DayTagRecord>()];
    expect(
      [for (final r in records) (r.date, r.tag)],
      [('2026-11-05', 'sick'), ('2026-11-09', 'travel')],
    );
  });

  test('CSV carries the date and tag rows', () async {
    final result = await exporter.export(request(ExportFormat.csv));

    expect(
      File(result.files.single.path).readAsStringSync(),
      'date,tag\r\n'
      '2026-11-05,sick\r\n'
      '2026-11-09,travel\r\n',
    );
    expect(result.counts, {ExportKind.dayTags: 2});
  });

  test('JSON carries the date and tag rows under day_tags', () async {
    final result = await exporter.export(request(ExportFormat.json));

    final json = jsonDecode(
      File(result.files.single.path).readAsStringSync(),
    ) as Map<String, Object?>;
    expect(json['day_tags'], [
      {'date': '2026-11-05', 'tag': 'sick'},
      {'date': '2026-11-09', 'tag': 'travel'},
    ]);
  });

  test('an empty table exports a header and an empty array', () async {
    await db.customStatement('DELETE FROM day_tags');

    final csv = await exporter.export(request(ExportFormat.csv));
    final json = await exporter.export(request(ExportFormat.json));

    expect(File(csv.files.single.path).readAsStringSync(), 'date,tag\r\n');
    final document = jsonDecode(
      File(json.files.single.path).readAsStringSync(),
    ) as Map<String, Object?>;
    expect(document['day_tags'], isEmpty);
  });

  test(
    'a tag on the local date of either end of the range is exported',
    () async {
      final edges = await pairedDatabase(pairedAt: DateTime.utc(2026, 11));
      addTearDown(edges.close);
      await edges.customStatement(
        'INSERT INTO day_tags (date, tag, updated_at_utc_ms) VALUES '
        "('2026-11-02', 'rest', 1), ('2026-11-03', 'sick', 1), "
        "('2026-11-11', 'travel', 1), ('2026-11-12', 'rest', 1)",
      );

      // Local noons, so the dates they fall on are the same in every zone.
      final pages = await ExportPagesDao(edges)
          .pages(
            ExportKind.dayTags,
            from: DateTime(2026, 11, 3, 12),
            to: DateTime(2026, 11, 11, 12),
          )
          .toList();

      final records = [for (final page in pages) ...page.cast<DayTagRecord>()];
      expect([for (final r in records) r.date], ['2026-11-03', '2026-11-11']);
    },
  );
}
