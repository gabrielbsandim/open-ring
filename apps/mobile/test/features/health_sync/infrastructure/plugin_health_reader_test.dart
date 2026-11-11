import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_reader.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_writer.dart';
import 'package:ring_driver/ring_driver.dart';

final class _FakeReadGateway implements HealthReadGateway {
  bool installed = true;
  bool granted = false;
  bool background = false;
  final List<List<HealthDataType>> requested = [];
  final Map<HealthDataType, List<HealthDataPoint>> points = {};
  final List<List<HealthDataType>> reads = [];

  @override
  Future<bool> available() async => installed;

  @override
  Future<bool> hasReadAccess(List<HealthDataType> types) async => granted;

  @override
  Future<bool> requestReadAccess(List<HealthDataType> types) async {
    requested.add(types);
    return true;
  }

  @override
  Future<bool> backgroundReadAllowed() async => background;

  @override
  Future<List<HealthDataPoint>> read(
    List<HealthDataType> types, {
    required DateTime from,
    required DateTime to,
  }) async {
    reads.add(types);
    return [for (final type in types) ...?points[type]];
  }
}

final class _FakeExercise implements ExerciseSessionSource {
  new(this.sessions);

  final List<ExternalWorkout> sessions;
  int reads = 0;

  @override
  Future<ExternalRead<ExternalWorkout>> read({
    required DateTime from,
    required DateTime to,
  }) async {
    reads++;
    return ExternalRead(sessions);
  }
}

final class _FakeSleepIds implements SleepSessionIdSource {
  new(this.known);

  final Set<String>? known;

  @override
  Future<Set<String>?> ids({
    required DateTime from,
    required DateTime to,
  }) async => known;
}

HealthDataPoint _point(
  HealthDataType type,
  String uuid,
  DateTime from,
  DateTime to, {
  String source = 'com.garmin.android.apps.connectmobile',
}) => HealthDataPoint(
  uuid: uuid,
  value: NumericHealthValue(numericValue: to.difference(from).inMinutes),
  type: type,
  unit: HealthDataUnit.MINUTE,
  dateFrom: from,
  dateTo: to,
  sourcePlatform: HealthPlatformType.googleHealthConnect,
  sourceDeviceId: 'phone',
  sourceId: '',
  sourceName: source,
);

void main() {
  final start = DateTime.utc(2026, 11, 9, 23);
  final mid = start.add(const Duration(hours: 3));
  final end = start.add(const Duration(hours: 7));

  late _FakeReadGateway gateway;

  setUp(() => gateway = _FakeReadGateway());

  PluginHealthReader reader({bool background = false}) => PluginHealthReader(
    gateway,
    HealthPlatform.healthConnect,
    background: background,
  );

  test('access follows Health Connect state and the read grant', () async {
    expect(
      await reader().readAccess(HealthRecordKind.sleep),
      HealthAccess.denied,
    );
    gateway.granted = true;
    expect(
      await reader().readAccess(HealthRecordKind.sleep),
      HealthAccess.granted,
    );
    gateway.installed = false;
    expect(
      await reader().readAccess(HealthRecordKind.sleep),
      HealthAccess.unavailable,
    );
  });

  test('the background engine waits without background read access', () async {
    gateway.granted = true;

    expect(
      await reader(background: true).readAccess(HealthRecordKind.sleep),
      HealthAccess.deferred,
    );
    gateway.background = true;
    expect(
      await reader(background: true).readAccess(HealthRecordKind.sleep),
      HealthAccess.granted,
    );
  });

  test('asks for each type on its own, exercise only for workouts', () async {
    await reader().requestReadAccess(HealthRecordKind.sleep);
    await reader().requestReadAccess(HealthRecordKind.workout);

    expect(gateway.requested, [
      [HealthDataType.SLEEP_SESSION],
      [HealthDataType.WORKOUT],
    ]);
    expect(
      await reader().requestReadAccess(HealthRecordKind.heartRate),
      isFalse,
    );
  });

  test('workouts come from the exercise source, never the plugin', () async {
    final watch = _FakeExercise([
      ExternalWorkout(
        recordId: 'w1',
        source: 'com.garmin.android.apps.connectmobile',
        activityType: 'running',
        start: start,
        end: mid,
        utcOffset: Duration.zero,
      ),
    ]);
    final health = PluginHealthReader(
      gateway,
      HealthPlatform.healthConnect,
      exercise: watch,
    );
    final kit = PluginHealthReader(
      gateway,
      HealthPlatform.healthKit,
      exercise: watch,
    );

    expect(
      (await health.workouts(from: start, to: end)).records.single.recordId,
      'w1',
    );
    expect((await kit.workouts(from: start, to: end)).records, isEmpty);
    expect(watch.reads, 1);
    expect(gateway.reads, isEmpty);
  });

  test('HealthKit reading is not built and reports unavailable', () async {
    final kit = PluginHealthReader(gateway, HealthPlatform.healthKit);
    gateway.granted = true;

    expect(
      await kit.readAccess(HealthRecordKind.sleep),
      HealthAccess.unavailable,
    );
    expect((await kit.sleepNights(from: start, to: end)).records, isEmpty);
    expect(gateway.reads, isEmpty);
  });

  test('groups stages under the session they belong to', () async {
    gateway.points
      ..[HealthDataType.SLEEP_SESSION] = [
        _point(HealthDataType.SLEEP_SESSION, 's1', start, end),
      ]
      ..[HealthDataType.SLEEP_REM] = [
        _point(HealthDataType.SLEEP_REM, 's1', mid, end),
      ]
      ..[HealthDataType.SLEEP_ASLEEP] = [
        _point(HealthDataType.SLEEP_ASLEEP, 's1', start, mid),
      ]
      ..[HealthDataType.SLEEP_AWAKE] = [
        _point(HealthDataType.SLEEP_AWAKE, 'other', start, mid),
      ];

    final nights = (await reader().sleepNights(from: start, to: end)).records;

    final night = nights.single;
    expect(night.recordId, 's1');
    expect(night.source, 'com.garmin.android.apps.connectmobile');
    expect(night.start, start);
    expect(night.end, end);
    expect(night.stages.map((s) => (s.start, s.stage)), [
      (start, SleepStage.light),
      (mid, SleepStage.rem),
    ]);
  });

  test(
    'nights carry the session ids only a reporting read can prove',
    () async {
      gateway.points[HealthDataType.SLEEP_SESSION] = [
        _point(HealthDataType.SLEEP_SESSION, 's1', start, end),
      ];
      final proven = PluginHealthReader(
        gateway,
        HealthPlatform.healthConnect,
        sleepIds: _FakeSleepIds({'s1', 's2'}),
      );

      expect((await proven.sleepNights(from: start, to: end)).present, {
        's1',
        's2',
      });
      expect(
        (await reader().sleepNights(from: start, to: end)).present,
        isNull,
      );
    },
  );

  test('reads no stages when there is no session', () async {
    expect((await reader().sleepNights(from: start, to: end)).records, isEmpty);
    expect(gateway.reads, [
      [HealthDataType.SLEEP_SESSION],
    ]);
  });
}
