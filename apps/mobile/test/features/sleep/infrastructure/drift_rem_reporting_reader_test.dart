import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:open_ring/features/ring/infrastructure/sleep_dao.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_rem_reporting_reader.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';

const _otherRing = RingIdentity(
  deviceId: 'R09_BEEF',
  name: 'R09_BEEF',
  model: 'R09',
);

List<SleepSegment> _night(int day, {SleepStage second = SleepStage.deep}) {
  final start = DateTime.utc(2026, 10, day, 23);
  final mid = start.add(const Duration(hours: 3));
  final end = mid.add(const Duration(hours: 2));
  return [
    SleepSegment(start: start, end: mid, stage: SleepStage.light),
    SleepSegment(start: mid, end: end, stage: second),
    SleepSegment(
      start: end,
      end: end.add(const Duration(minutes: 20)),
      stage: SleepStage.awake,
    ),
  ];
}

Future<void> _nights(
  AppDatabase db,
  Iterable<int> days, {
  String deviceId = ringId,
  Set<int> remOn = const {},
}) => SleepDao(db).replaceNights(deviceId, [
  for (final day in days)
    ..._night(
      day,
      second: remOn.contains(day) ? SleepStage.rem : SleepStage.deep,
    ),
]);

void main() {
  late AppDatabase db;
  late DriftRemReportingReader reader;

  setUp(() async {
    db = await pairedDatabase();
    reader = DriftRemReportingReader(db);
  });

  test('with no ring paired nothing is known', () async {
    expect(
      await DriftRemReportingReader(memoryDatabase()).pairedRing(),
      RemReporting.unknown,
    );
  });

  test('six nights without REM are not yet a verdict', () async {
    await _nights(db, [for (var day = 1; day <= 6; day++) day]);

    expect(await reader.pairedRing(), RemReporting.unknown);
  });

  test('seven nights without REM mean the ring does not report it', () async {
    await _nights(db, [for (var day = 1; day <= 7; day++) day]);

    expect(await reader.pairedRing(), RemReporting.absent);
  });

  test('one night with REM, ever, means the ring reports it', () async {
    await _nights(db, [for (var day = 1; day <= 20; day++) day], remOn: {3});

    expect(await reader.pairedRing(), RemReporting.reported);
  });

  test('a night the ring split in two counts once', () async {
    final dao = SleepDao(db);
    for (var day = 1; day <= 6; day++) {
      final first = _night(day);
      final later = first.last.end.add(const Duration(hours: 2));
      await dao.replaceNights(ringId, [
        ...first,
        SleepSegment(
          start: later,
          end: later.add(const Duration(minutes: 40)),
          stage: SleepStage.light,
        ),
      ]);
    }

    expect(await reader.pairedRing(), RemReporting.unknown);
  });

  test('a session of awake time only is not a night', () async {
    await _nights(db, [for (var day = 1; day <= 6; day++) day]);
    final start = DateTime.utc(2026, 10, 20, 23);
    await SleepDao(db).replaceNights(ringId, [
      SleepSegment(
        start: start,
        end: start.add(const Duration(hours: 1)),
        stage: SleepStage.awake,
      ),
    ]);

    expect(await reader.pairedRing(), RemReporting.unknown);
  });

  test('only the paired ring counts', () async {
    await RingDevicesDao(db).pair(_otherRing, at: DateTime(2026, 12));
    await _nights(db, [for (var day = 1; day <= 7; day++) day], remOn: {2});
    await _nights(db, [
      for (var day = 1; day <= 7; day++) day,
    ], deviceId: _otherRing.deviceId);

    expect(await reader.pairedRing(), RemReporting.absent);
  });
}
