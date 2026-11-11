import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/domain/json_export_writer.dart';
import 'package:open_ring/features/export/domain/offset_time.dart';

OffsetTime _at(DateTime utc, int offsetMinutes) =>
    OffsetTime(utcMs: utc.millisecondsSinceEpoch, offsetMinutes: offsetMinutes);

final _header = ExportHeader(
  exportedAt: _at(DateTime.utc(2026, 11, 10, 15), -180),
  from: _at(DateTime.utc(2026, 10, 24, 22), 120),
  to: _at(DateTime.utc(2026, 10, 25, 23), 60),
  device: const ExportDevice(id: 'R09_C0FE', name: 'R09_C0FE', model: 'R09'),
);

void main() {
  test('golden document with a DST night, an empty kind and a workout', () {
    final buffer = StringBuffer();
    JsonExportWriter(buffer)
      ..begin(_header)
      ..beginKind(ExportKind.heartRate)
      ..write(
        SampleRecord(
          at: _at(DateTime.utc(2026, 10, 25, 0, 30), 120),
          deviceId: 'R09_C0FE',
          value: 58,
        ),
      )
      ..write(
        SampleRecord(
          at: _at(DateTime.utc(2026, 10, 25, 1, 30), 60),
          deviceId: 'R09_C0FE',
          value: 57,
        ),
      )
      ..endKind()
      ..beginKind(ExportKind.hrv)
      ..endKind()
      ..beginKind(ExportKind.workouts)
      ..write(
        WorkoutRecord(
          start: _at(DateTime.utc(2026, 10, 25, 9), 60),
          clientId: 'w-1',
          activityType: 'run "tempo"',
          activeKilocalories: 250,
        ),
      )
      ..endKind()
      ..end();

    expect(
      buffer.toString(),
      '{\n'
      '  "schema_version": 1,\n'
      '  "exported_at": "2026-11-10T12:00:00-03:00",\n'
      '  "range": {"from":"2026-10-25T00:00:00+02:00","to":"2026-10-26T00:00:00+01:00"},\n'
      '  "device": {"id":"R09_C0FE","name":"R09_C0FE","model":"R09","firmware":null},\n'
      '  "heart_rate": [\n'
      '    {"time":"2026-10-25T02:30:00+02:00","device_id":"R09_C0FE","bpm":58},\n'
      '    {"time":"2026-10-25T02:30:00+01:00","device_id":"R09_C0FE","bpm":57}\n'
      '  ],\n'
      '  "hrv": [],\n'
      '  "workouts": [\n'
      r'    {"start":"2026-10-25T10:00:00+01:00","end":null,"client_id":"w-1","device_id":null,"activity_type":"run \"tempo\"","duration_s":null,"distance_m":null,"active_kcal":250}'
      '\n'
      '  ]\n'
      '}\n',
    );
    expect(() => jsonDecode(buffer.toString()), returnsNormally);
  });

  test('a document with no device and no kinds is still valid JSON', () {
    final buffer = StringBuffer();
    JsonExportWriter(buffer)
      ..begin(
        ExportHeader(
          exportedAt: _header.exportedAt,
          from: _header.from,
          to: _header.to,
        ),
      )
      ..end();

    final decoded = jsonDecode(buffer.toString()) as Map<String, Object?>;

    expect(decoded.keys, ['schema_version', 'exported_at', 'range', 'device']);
    expect(decoded['device'], isNull);
  });

  test('every column of every kind becomes a key, in column order', () {
    final record = exportRecordJson(
      ExportKind.activity,
      ActivityRecord(
        start: _at(DateTime.utc(2026, 11, 10, 12), -180),
        duration: const Duration(minutes: 15),
        deviceId: 'R09_C0FE',
        steps: 812,
        distanceMeters: 590,
        activeKilocalories: 31.456,
      ),
    );

    expect(record.keys, ExportKind.activity.columns);
    expect(record['end'], '2026-11-10T09:15:00-03:00');
    expect(record['active_kcal'], 31.46);
  });

  test('misuse is a StateError', () {
    final record = SampleRecord(
      at: _at(DateTime.utc(2026, 11, 10), 0),
      deviceId: 'R09_C0FE',
      value: 60,
    );

    expect(
      () => JsonExportWriter(StringBuffer()).write(record),
      throwsStateError,
    );
    expect(
      () => JsonExportWriter(StringBuffer()).beginKind(ExportKind.hrv),
      throwsStateError,
    );
    expect(
      () => JsonExportWriter(StringBuffer())
        ..begin(_header)
        ..beginKind(ExportKind.hrv)
        ..end(),
      throwsStateError,
    );
  });
}
