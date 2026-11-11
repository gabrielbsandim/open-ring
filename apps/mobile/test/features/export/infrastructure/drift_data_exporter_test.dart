import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/features/export/application/export_providers.dart';
import 'package:open_ring/features/export/domain/data_exporter.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_request.dart';
import 'package:open_ring/features/export/infrastructure/drift_data_exporter.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:xml/xml.dart';

import '../../../helpers/database.dart';

const _otherRing = 'R02_0001';

final _now = DateTime.utc(2026, 11, 10, 15);
final _from = DateTime.utc(2026, 10, 24, 22);
final _to = DateTime.utc(2026, 10, 25, 23);

int _ms(DateTime at) => at.millisecondsSinceEpoch;

Future<void> _seed(AppDatabase db) async {
  await RingDevicesDao(db).pair(
    const RingIdentity(deviceId: _otherRing, name: 'R02_0001'),
    at: DateTime.utc(2026, 10),
  );
  for (final (device, at, offset, bpm) in [
    (ringId, _from.subtract(const Duration(minutes: 1)), 120, 99),
    (ringId, DateTime.utc(2026, 10, 25, 0, 30), 120, 58),
    (_otherRing, DateTime.utc(2026, 10, 25, 0, 30), 120, 63),
    (ringId, DateTime.utc(2026, 10, 25, 1, 30), 60, 57),
    (_otherRing, DateTime.utc(2026, 10, 25, 1, 30), 60, 62),
    (ringId, DateTime.utc(2026, 10, 25, 2, 30), 60, 61),
    (ringId, _to, 60, 98),
  ]) {
    await db
        .into(db.hrSamples)
        .insert(
          HrSamplesCompanion.insert(
            deviceId: device,
            atUtcMs: _ms(at),
            offsetMinutes: offset,
            bpm: bpm,
          ),
        );
  }

  final before = DateTime.utc(2026, 10, 24, 21);
  final night = DateTime.utc(2026, 10, 24, 23);
  for (final (start, end) in [
    (before, DateTime.utc(2026, 10, 24, 21, 50)),
    (night, DateTime.utc(2026, 10, 25, 2)),
  ]) {
    await db
        .into(db.sleepSessions)
        .insert(
          SleepSessionsCompanion.insert(
            deviceId: ringId,
            startUtcMs: _ms(start),
            endUtcMs: _ms(end),
            offsetMinutes: 120,
          ),
        );
  }
  for (final (sessionStart, start, end, offset, stage) in [
    (before, before, DateTime.utc(2026, 10, 24, 21, 50), 120, SleepStage.light),
    (night, night, DateTime.utc(2026, 10, 25, 1, 15), 120, SleepStage.deep),
    (
      night,
      DateTime.utc(2026, 10, 25, 1, 15),
      DateTime.utc(2026, 10, 25, 2),
      60,
      SleepStage.rem,
    ),
  ]) {
    await db
        .into(db.sleepSegments)
        .insert(
          SleepSegmentsCompanion.insert(
            deviceId: ringId,
            startUtcMs: _ms(start),
            endUtcMs: _ms(end),
            offsetMinutes: offset,
            stage: stage,
            sessionStartUtcMs: _ms(sessionStart),
          ),
        );
  }

  await db
      .into(db.activityBuckets)
      .insert(
        ActivityBucketsCompanion.insert(
          deviceId: ringId,
          startUtcMs: _ms(DateTime.utc(2026, 10, 25, 8)),
          offsetMinutes: 60,
          durationSeconds: 900,
          steps: 812,
          distanceMeters: 590,
          activeKilocalories: 31.5,
        ),
      );

  for (final (clientId, start, end) in [
    ('w-2', DateTime.utc(2026, 10, 25, 18), null),
    ('w-1', DateTime.utc(2026, 10, 25, 9), DateTime.utc(2026, 10, 25, 9, 40)),
  ]) {
    await db
        .into(db.workouts)
        .insert(
          WorkoutsCompanion.insert(
            clientId: clientId,
            activityType: 'running',
            startUtcMs: _ms(start),
            endUtcMs: Value.absentIfNull(end == null ? null : _ms(end)),
            offsetMinutes: 60,
            distanceMeters: const Value(6012.3),
          ),
        );
  }
}

ExportRequest _request(ExportFormat format, List<ExportKind> kinds) =>
    ExportRequest(from: _from, to: _to, kinds: kinds, format: format);

void main() {
  late AppDatabase db;
  late Directory root;
  late DriftDataExporter exporter;

  setUp(() async {
    db = await pairedDatabase(pairedAt: DateTime.utc(2026, 11));
    await _seed(db);
    root = Directory.systemTemp.createTempSync('openring_export_test_');
    addTearDown(() => root.delete(recursive: true));
    exporter = DriftDataExporter(
      database: db,
      clock: () => _now,
      directory: () async => root,
      pageSize: 2,
    );
  });

  group('CSV', () {
    test(
      'several kinds are zipped into one archive, a file per kind',
      () async {
        final result = await exporter.export(
          _request(ExportFormat.csv, const [
            ExportKind.hrv,
            ExportKind.heartRate,
            ExportKind.sleep,
          ]),
        );

        final file = result.files.single;
        expect(file.mimeType, ExportFile.zipMimeType);
        expect(file.path, endsWith('openring-csv-20261110-150000.zip'));
        expect(File(file.path).parent.listSync(), hasLength(1));
        final archive = ZipDecoder().decodeBytes(
          File(file.path).readAsBytesSync(),
        );
        final entries = {
          for (final entry in archive.files)
            entry.name: utf8.decode(entry.content),
        };
        expect(entries.keys, ['sleep.csv', 'heart_rate.csv', 'hrv.csv']);
        expect(
          entries['heart_rate.csv'],
          'time,device_id,bpm\r\n'
          '2026-10-25T02:30:00+02:00,R02_0001,63\r\n'
          '2026-10-25T02:30:00+02:00,R09_C0FE,58\r\n'
          '2026-10-25T02:30:00+01:00,R02_0001,62\r\n'
          '2026-10-25T02:30:00+01:00,R09_C0FE,57\r\n'
          '2026-10-25T03:30:00+01:00,R09_C0FE,61\r\n',
        );
        expect(
          entries['sleep.csv'],
          'session_start,start,end,device_id,stage,duration_s\r\n'
          '2026-10-25T01:00:00+02:00,2026-10-25T01:00:00+02:00,'
          '2026-10-25T03:15:00+02:00,R09_C0FE,deep,8100\r\n'
          '2026-10-25T01:00:00+02:00,2026-10-25T02:15:00+01:00,'
          '2026-10-25T03:00:00+01:00,R09_C0FE,rem,2700\r\n',
        );
        expect(entries['hrv.csv'], 'time,device_id,hrv_ms\r\n');
        expect(result.counts, {
          ExportKind.sleep: 2,
          ExportKind.heartRate: 5,
          ExportKind.hrv: 0,
        });
        expect(result.recordCount, 7);
      },
    );

    test('a single kind is a plain CSV file', () async {
      final result = await exporter.export(
        _request(ExportFormat.csv, const [ExportKind.workouts]),
      );

      final file = result.files.single;
      expect(file.mimeType, ExportFile.csvMimeType);
      expect(file.path, endsWith('openring-workouts-20261110-150000.csv'));
      expect(
        File(file.path).readAsStringSync(),
        'start,end,client_id,device_id,activity_type,duration_s,distance_m,active_kcal\r\n'
        '2026-10-25T10:00:00+01:00,2026-10-25T10:40:00+01:00,w-1,,running,2400,6012.3,\r\n'
        '2026-10-25T19:00:00+01:00,,w-2,,running,,6012.3,\r\n',
      );
    });

    test('each export gets its own folder', () async {
      final request = _request(ExportFormat.csv, const [ExportKind.activity]);

      final first = await exporter.export(request);
      final second = await exporter.export(request);

      expect(first.files.single.path, isNot(second.files.single.path));
      expect(File(first.files.single.path).existsSync(), isTrue);
    });
  });

  test('JSON is one document with the device and an array per kind', () async {
    final result = await exporter.export(
      _request(ExportFormat.json, ExportKind.values),
    );

    final file = result.files.single;
    expect(file.mimeType, ExportFile.jsonMimeType);
    expect(file.path, endsWith('openring-20261110-150000.json'));
    final json =
        jsonDecode(File(file.path).readAsStringSync()) as Map<String, Object?>;
    expect(json.keys, [
      'schema_version',
      'exported_at',
      'range',
      'device',
      for (final kind in ExportKind.values) kind.key,
    ]);
    expect(json['schema_version'], 1);
    expect(json['exported_at'], '2026-11-10T15:00:00+00:00');
    expect(json['range'], {
      'from': '2026-10-24T22:00:00+00:00',
      'to': '2026-10-25T23:00:00+00:00',
    });
    expect(json['device'], {
      'id': ringId,
      'name': ringIdentity.name,
      'model': 'R09',
      'firmware': null,
    });
    expect(json['heart_rate'], hasLength(5));
    expect(json['sleep'], hasLength(2));
    expect(json['hrv'], isEmpty);
    expect(json['activity'], [
      {
        'start': '2026-10-25T09:00:00+01:00',
        'end': '2026-10-25T09:15:00+01:00',
        'device_id': ringId,
        'steps': 812,
        'distance_m': 590,
        'active_kcal': 31.5,
      },
    ]);
    expect(
      [
        for (final w in json['workouts']! as List<Object?>)
          (w! as Map<String, Object?>)['client_id'],
      ],
      ['w-1', 'w-2'],
    );
    expect(result.recordCount, 10);
  });

  test('a failed export leaves no folder behind', () async {
    await db.close();

    await expectLater(
      exporter.export(_request(ExportFormat.json, const [ExportKind.hrv])),
      throwsA(anything),
    );
    expect(root.listSync(), isEmpty);
  });

  test('a route is written as a GPX file', () async {
    final file = await exporter.exportRoute(
      WorkoutRoute(
        name: 'Run',
        segments: [
          [
            TrackPoint(
              at: DateTime.utc(2026, 10, 25, 9),
              latitude: 52.52,
              longitude: 13.405,
              heartRateBpm: 120,
            ),
          ],
        ],
      ),
    );

    expect(file.mimeType, ExportFile.gpxMimeType);
    expect(file.path, endsWith('openring-route-20261110-150000.gpx'));
    final gpx = XmlDocument.parse(File(file.path).readAsStringSync());
    expect(gpx.findAllElements('trkpt'), hasLength(1));
  });

  test('a workout is written as a CSV file', () async {
    final start = DateTime.utc(2026, 10, 25, 9);
    final file = await exporter.exportWorkoutCsv(
      FinishedWorkout(
        type: WorkoutType.running,
        start: start,
        end: start.add(const Duration(minutes: 1)),
        elapsed: const Duration(minutes: 1),
        heartRate: [(at: start, bpm: 120)],
        route: WorkoutRoute(segments: const []),
        pauses: const [],
      ),
      offset: const Duration(hours: 1),
    );

    expect(file.mimeType, ExportFile.csvMimeType);
    expect(file.path, endsWith('openring-workout-20261110-150000.csv'));
    expect(
      File(file.path).readAsStringSync(),
      'time,bpm,latitude,longitude,elevation_m,accuracy_m\r\n'
      '2026-10-25T10:00:00+01:00,120,,,,\r\n',
    );
  });

  test('the provider builds the drift exporter over the app database', () {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => _now),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(dataExporterProvider), isA<DriftDataExporter>());
  });
}
