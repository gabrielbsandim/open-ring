import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/export/domain/csv_export_writer.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/domain/export_values.dart';
import 'package:open_ring/features/export/domain/offset_time.dart';
import 'package:ring_driver/ring_driver.dart';

OffsetTime _at(DateTime utc, int offsetMinutes) =>
    OffsetTime(utcMs: utc.millisecondsSinceEpoch, offsetMinutes: offsetMinutes);

String _csv(ExportKind kind, List<ExportRecord> records) {
  final buffer = StringBuffer();
  final writer = CsvExportWriter(kind, buffer)..writeHeader();
  records.forEach(writer.write);
  return buffer.toString();
}

void main() {
  group('csvField', () {
    test('leaves plain text unquoted', () {
      expect(csvField('R09_C0FE'), 'R09_C0FE');
      expect(csvField(''), '');
      expect(csvField(' padded '), ' padded ');
    });

    test('quotes commas, quotes, CR and LF and doubles inner quotes', () {
      expect(csvField('a,b'), '"a,b"');
      expect(csvField('say "hi"'), '"say ""hi"""');
      expect(csvField('line\nbreak'), '"line\nbreak"');
      expect(csvField('carriage\rreturn'), '"carriage\rreturn"');
      expect(csvField('"'), '""""');
    });
  });

  group('OffsetTime', () {
    test('renders wall clock time with the stored offset', () {
      final instant = DateTime.utc(2026, 11, 10, 12, 5, 9);
      expect(_at(instant, -180).toIso8601(), '2026-11-10T09:05:09-03:00');
      expect(_at(instant, 0).toIso8601(), '2026-11-10T12:05:09+00:00');
      expect(_at(instant, 345).toIso8601(), '2026-11-10T17:50:09+05:45');
      expect(_at(instant, -570).toIso8601(), '2026-11-10T02:35:09-09:30');
    });

    test('crosses the date line and keeps milliseconds only when set', () {
      final late = DateTime.utc(2026, 12, 31, 23, 30, 0, 250);
      expect(_at(late, 60).toIso8601(), '2027-01-01T00:30:00.250+01:00');
      expect(_at(late, 60).toUtcIso8601(), '2026-12-31T23:30:00.250Z');
    });
  });

  test('formatDecimal is stable and trims trailing zeros', () {
    expect(formatDecimal(12), '12');
    expect(formatDecimal(12.5), '12.5');
    expect(formatDecimal(12.345), '12.35');
    expect(formatDecimal(-0.001), '0');
    expect(formatDecimal(double.nan), '');
  });

  test('heart rate golden across the Europe/Berlin fall back', () {
    final csv = _csv(ExportKind.heartRate, [
      SampleRecord(
        at: _at(DateTime.utc(2026, 10, 25, 0, 30), 120),
        deviceId: 'R09_C0FE',
        value: 58,
      ),
      SampleRecord(
        at: _at(DateTime.utc(2026, 10, 25, 1, 30), 60),
        deviceId: 'R09_C0FE',
        value: 57,
      ),
      SampleRecord(
        at: _at(DateTime.utc(2026, 10, 25, 2, 30), 60),
        deviceId: 'R09_C0FE',
        value: 61,
      ),
    ]);

    expect(
      csv,
      'time,device_id,bpm\r\n'
      '2026-10-25T02:30:00+02:00,R09_C0FE,58\r\n'
      '2026-10-25T02:30:00+01:00,R09_C0FE,57\r\n'
      '2026-10-25T03:30:00+01:00,R09_C0FE,61\r\n',
    );
  });

  test('sleep golden across the America/New_York spring forward', () {
    final sessionStart = _at(DateTime.utc(2026, 3, 8, 6), -300);
    final csv = _csv(ExportKind.sleep, [
      SleepStageRecord(
        sessionStart: sessionStart,
        start: sessionStart,
        end: _at(DateTime.utc(2026, 3, 8, 7, 30), -300),
        deviceId: 'R09_C0FE',
        stage: SleepStage.light,
      ),
      SleepStageRecord(
        sessionStart: sessionStart,
        start: _at(DateTime.utc(2026, 3, 8, 7, 30), -240),
        end: _at(DateTime.utc(2026, 3, 8, 8, 15), -240),
        deviceId: 'R09_C0FE',
        stage: SleepStage.rem,
      ),
    ]);

    expect(
      csv,
      'session_start,start,end,device_id,stage,duration_s\r\n'
      '2026-03-08T01:00:00-05:00,2026-03-08T01:00:00-05:00,'
      '2026-03-08T02:30:00-05:00,R09_C0FE,light,5400\r\n'
      '2026-03-08T01:00:00-05:00,2026-03-08T03:30:00-04:00,'
      '2026-03-08T04:15:00-04:00,R09_C0FE,rem,2700\r\n',
    );
  });

  test('activity golden derives end from duration and formats kcal', () {
    final csv = _csv(ExportKind.activity, [
      ActivityRecord(
        start: _at(DateTime.utc(2026, 11, 10, 12), -180),
        duration: const Duration(minutes: 15),
        deviceId: 'R09_C0FE',
        steps: 812,
        distanceMeters: 590,
        activeKilocalories: 31.5,
      ),
    ]);

    expect(
      csv,
      'start,end,device_id,steps,distance_m,active_kcal\r\n'
      '2026-11-10T09:00:00-03:00,2026-11-10T09:15:00-03:00,R09_C0FE,812,590,31.5\r\n',
    );
  });

  test('workout golden quotes free text and leaves missing values empty', () {
    final csv = _csv(ExportKind.workouts, [
      WorkoutRecord(
        start: _at(DateTime.utc(2026, 11, 10, 10), 0),
        end: _at(DateTime.utc(2026, 11, 10, 10, 42, 30), 0),
        clientId: 'w-1',
        deviceId: 'R09_C0FE',
        activityType: 'run, "easy"\nlap',
        distanceMeters: 6012.345,
        activeKilocalories: 402,
      ),
      WorkoutRecord(
        start: _at(DateTime.utc(2026, 11, 10, 18), 0),
        clientId: 'w-2',
        activityType: 'walk',
      ),
    ]);

    expect(
      csv,
      'start,end,client_id,device_id,activity_type,duration_s,distance_m,active_kcal\r\n'
      '2026-11-10T10:00:00+00:00,2026-11-10T10:42:30+00:00,w-1,R09_C0FE,'
      '"run, ""easy""\nlap",2550,6012.35,402\r\n'
      '2026-11-10T18:00:00+00:00,,w-2,,walk,,,\r\n',
    );
  });

  test('an empty kind still writes its header row', () {
    for (final kind in ExportKind.values) {
      expect(_csv(kind, const []), '${kind.columns.join(',')}\r\n');
    }
  });

  test('a record that does not fit the kind is rejected', () {
    final record = SampleRecord(
      at: _at(DateTime.utc(2026, 11, 10), 0),
      deviceId: 'R09_C0FE',
      value: 60,
    );

    expect(() => _csv(ExportKind.activity, [record]), throwsArgumentError);
  });
}
