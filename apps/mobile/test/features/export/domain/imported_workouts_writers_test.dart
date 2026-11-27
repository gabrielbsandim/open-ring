import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/export/domain/csv_export_writer.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/domain/json_export_writer.dart';
import 'package:open_ring/features/export/domain/offset_time.dart';

OffsetTime _at(DateTime utc, int offsetMinutes) =>
    OffsetTime(utcMs: utc.millisecondsSinceEpoch, offsetMinutes: offsetMinutes);

final _rows = [
  ImportedWorkoutRecord(
    start: _at(DateTime.utc(2026, 11, 10, 10), -180),
    end: _at(DateTime.utc(2026, 11, 10, 10, 42, 30), -180),
    recordId: 'r-1',
    source: 'com.garmin,connect',
    activityType: 'running',
    effortRating: 7,
  ),
  ImportedWorkoutRecord(
    start: _at(DateTime.utc(2026, 11, 10, 18), 0),
    end: _at(DateTime.utc(2026, 11, 10, 18, 5), 0),
    recordId: 'r-2',
    source: 'plain',
    activityType: 'walking',
  ),
];

final _header = ExportHeader(
  exportedAt: _at(DateTime.utc(2026, 11, 10, 15), 0),
  from: _at(DateTime.utc(2026, 11), 0),
  to: _at(DateTime.utc(2026, 11, 11), 0),
);

void main() {
  test('csv golden has a header and CRLF rows, a comma is quoted', () {
    final buffer = StringBuffer();
    final writer = CsvExportWriter(ExportKind.importedWorkouts, buffer)
      ..writeHeader();
    _rows.forEach(writer.write);

    expect(
      buffer.toString(),
      'start,end,record_id,source,activity_type,duration_s,effort_rating\r\n'
      '2026-11-10T07:00:00-03:00,2026-11-10T07:42:30-03:00,r-1,'
      '"com.garmin,connect",running,2550,7\r\n'
      '2026-11-10T18:00:00+00:00,2026-11-10T18:05:00+00:00,r-2,plain,walking,'
      '300,\r\n',
    );
  });

  test('an empty imported workouts kind still writes its header', () {
    final buffer = StringBuffer();
    CsvExportWriter(ExportKind.importedWorkouts, buffer).writeHeader();

    expect(
      buffer.toString(),
      'start,end,record_id,source,activity_type,duration_s,effort_rating\r\n',
    );
  });

  test('json puts the kind last and keeps schema_version at 1', () {
    final buffer = StringBuffer();
    final writer = JsonExportWriter(buffer)
      ..begin(_header)
      ..beginKind(ExportKind.dayTags)
      ..write(const DayTagRecord(date: '2026-11-10', tag: 'sick'))
      ..endKind()
      ..beginKind(ExportKind.importedWorkouts);
    _rows.forEach(writer.write);
    writer
      ..endKind()
      ..end();

    final decoded = jsonDecode(buffer.toString()) as Map<String, Object?>;

    expect(decoded['schema_version'], 1);
    expect(decoded.keys.last, 'imported_workouts');
    final rows = (decoded['imported_workouts']! as List)
        .cast<Map<String, dynamic>>();
    expect(rows.first.keys, ExportKind.importedWorkouts.columns);
    expect(rows.first['source'], 'com.garmin,connect');
    expect(rows.first['duration_s'], 2550);
    expect(rows.first['effort_rating'], 7);
    expect(rows.last['effort_rating'], isNull);
  });

  test('json record keys follow the column order', () {
    final record = exportRecordJson(ExportKind.importedWorkouts, _rows.first);

    expect(record.keys, ExportKind.importedWorkouts.columns);
    expect(record['end'], '2026-11-10T07:42:30-03:00');
  });
}
