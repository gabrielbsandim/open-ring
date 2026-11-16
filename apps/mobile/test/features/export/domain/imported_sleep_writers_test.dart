import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/export/domain/csv_export_writer.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/domain/json_export_writer.dart';
import 'package:open_ring/features/export/domain/offset_time.dart';
import 'package:ring_driver/ring_driver.dart';

OffsetTime _at(DateTime utc, int offsetMinutes) =>
    OffsetTime(utcMs: utc.millisecondsSinceEpoch, offsetMinutes: offsetMinutes);

final _rows = [
  ImportedSleepStageRecord(
    sessionStart: _at(DateTime.utc(2026, 11, 10, 1), -180),
    start: _at(DateTime.utc(2026, 11, 10, 1), -180),
    end: _at(DateTime.utc(2026, 11, 10, 1, 42, 30), -180),
    recordId: 'r-1',
    source: 'com.garmin,connect',
    stage: SleepStage.deep,
  ),
  ImportedSleepStageRecord(
    sessionStart: _at(DateTime.utc(2026, 11, 10, 22), 0),
    start: _at(DateTime.utc(2026, 11, 10, 22), 0),
    end: _at(DateTime.utc(2026, 11, 10, 22, 5), 0),
    recordId: 'r-2',
    source: 'plain',
    stage: SleepStage.awake,
  ),
];

final _header = ExportHeader(
  exportedAt: _at(DateTime.utc(2026, 11, 10, 15), 0),
  from: _at(DateTime.utc(2026, 11), 0),
  to: _at(DateTime.utc(2026, 11, 11), 0),
);

const _headerLine =
    'session_start,start,end,record_id,source,stage,duration_s\r\n';

void main() {
  test('csv golden has a header and CRLF rows, a comma is quoted', () {
    final buffer = StringBuffer();
    final writer = CsvExportWriter(ExportKind.importedSleep, buffer)
      ..writeHeader();
    _rows.forEach(writer.write);

    expect(
      buffer.toString(),
      '$_headerLine'
      '2026-11-09T22:00:00-03:00,2026-11-09T22:00:00-03:00,'
      '2026-11-09T22:42:30-03:00,r-1,"com.garmin,connect",deep,2550\r\n'
      '2026-11-10T22:00:00+00:00,2026-11-10T22:00:00+00:00,'
      '2026-11-10T22:05:00+00:00,r-2,plain,awake,300\r\n',
    );
  });

  test('an empty imported sleep kind still writes its header', () {
    final buffer = StringBuffer();
    CsvExportWriter(ExportKind.importedSleep, buffer).writeHeader();

    expect(buffer.toString(), _headerLine);
  });

  test('an empty imported sleep kind is an empty json array', () {
    final buffer = StringBuffer();
    JsonExportWriter(buffer)
      ..begin(_header)
      ..beginKind(ExportKind.importedSleep)
      ..endKind()
      ..end();

    final decoded = jsonDecode(buffer.toString()) as Map<String, Object?>;

    expect(decoded['imported_sleep'], isEmpty);
    expect(decoded['schema_version'], 1);
  });

  test('json puts the kind last and keeps schema_version at 1', () {
    final buffer = StringBuffer();
    final writer = JsonExportWriter(buffer)
      ..begin(_header)
      ..beginKind(ExportKind.dayTags)
      ..write(const DayTagRecord(date: '2026-11-10', tag: 'sick'))
      ..endKind()
      ..beginKind(ExportKind.importedSleep);
    _rows.forEach(writer.write);
    writer
      ..endKind()
      ..end();

    final decoded = jsonDecode(buffer.toString()) as Map<String, Object?>;

    expect(decoded['schema_version'], 1);
    expect(decoded.keys.last, 'imported_sleep');
    final rows = (decoded['imported_sleep']! as List)
        .cast<Map<String, dynamic>>();
    expect(rows.first.keys, ExportKind.importedSleep.columns);
    expect(rows.first['source'], 'com.garmin,connect');
    expect(rows.first['stage'], 'deep');
    expect(rows.first['duration_s'], 2550);
    expect(rows.last['stage'], 'awake');
  });

  test('json record keys follow the column order', () {
    final record = exportRecordJson(ExportKind.importedSleep, _rows.first);

    expect(record.keys, ExportKind.importedSleep.columns);
    expect(record['session_start'], '2026-11-09T22:00:00-03:00');
    expect(record['end'], '2026-11-09T22:42:30-03:00');
  });
}
