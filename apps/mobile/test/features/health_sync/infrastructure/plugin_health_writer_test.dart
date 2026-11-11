import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_writer.dart';
import 'package:ring_driver/ring_driver.dart';

final class FakeGateway implements HealthGateway {
  final calls = <String>[];
  final writes = <(HealthDataType, double, String, int)>[];
  bool isAvailable = true;
  bool granted = true;
  bool writeSucceeds = true;
  List<HealthDataType>? checked;

  @override
  Future<bool> available() async => isAvailable;

  @override
  Future<bool> hasWriteAccess(List<HealthDataType> types) async {
    checked = types;
    return granted;
  }

  @override
  Future<bool> requestWriteAccess(List<HealthDataType> types) async {
    checked = types;
    return true;
  }

  @override
  Future<bool> write(
    HealthDataType type,
    double value, {
    required DateTime start,
    required DateTime end,
    required String clientRecordId,
    required int version,
  }) async {
    calls.add('write ${type.name}');
    writes.add((type, value, clientRecordId, version));
    return writeSucceeds;
  }

  @override
  Future<bool> delete(
    HealthDataType type, {
    required DateTime from,
    required DateTime to,
  }) async {
    calls.add('delete ${type.name} ${from.hour}-${to.hour}');
    return true;
  }

  @override
  Future<String?> writeWorkout({
    required HealthWorkoutActivityType type,
    required DateTime start,
    required DateTime end,
    int? kilocalories,
    int? meters,
  }) async {
    calls.add('workout ${type.name} $kilocalories $meters');
    return 'uuid-1';
  }

  @override
  Future<bool> writeRoute(
    String workoutId,
    List<WorkoutRouteLocation> route,
  ) async {
    calls.add('route $workoutId ${route.length}');
    return true;
  }
}

final class FakeSleepSessions implements SleepSessionWriter {
  new(this.calls);

  final List<String> calls;
  final written = <(SleepEntry, int)>[];

  @override
  Future<void> deleteRange({
    required DateTime from,
    required DateTime to,
  }) async => calls.add('sleep delete ${from.hour}-${to.hour}');

  @override
  Future<void> write(SleepEntry night, {required int version}) async {
    calls.add('sleep write ${night.id} ${night.stages.length} stages');
    written.add((night, version));
  }
}

final class FakeHeartRateSeries implements HeartRateSeriesWriter {
  new(this.calls);

  final List<String> calls;
  final written = <(List<HeartRateSeriesEntry>, int, bool)>[];

  @override
  Future<void> deleteRange({
    required DateTime from,
    required DateTime to,
  }) async => calls.add('hr delete ${from.hour}-${to.hour}');

  @override
  Future<void> write(
    List<HeartRateSeriesEntry> series, {
    required int version,
    required bool active,
  }) async {
    calls.add('hr write ${series.length} series');
    written.add((series, version, active));
  }
}

final from = DateTime(2026, 11, 10, 1);
final to = DateTime(2026, 11, 10, 5);

HealthWriteBatch batch(HealthRecordKind kind, List<HealthEntry> entries) =>
    HealthWriteBatch(
      kind: kind,
      from: from,
      to: to,
      version: 42,
      entries: entries,
    );

final spo2 = Spo2Entry(id: 'spo2', at: from, percent: 97);
final hrv = HrvEntry(id: 'hrv', at: from, milliseconds: 55);
final night = SleepEntry(
  id: 'night',
  start: from,
  end: to,
  stages: [
    SleepStageEntry(
      id: 'light',
      start: from,
      end: DateTime(2026, 11, 10, 3),
      stage: SleepStage.light,
    ),
    SleepStageEntry(
      id: 'rem',
      start: DateTime(2026, 11, 10, 3),
      end: to,
      stage: SleepStage.rem,
    ),
  ],
);
final hourSeries = HeartRateSeriesEntry(
  id: 'hr-1',
  start: from,
  end: from.add(const Duration(minutes: 5)),
  samples: [
    HeartRateEntry(id: 'hr-1a', at: from, bpm: 61),
    HeartRateEntry(
      id: 'hr-1b',
      at: from.add(const Duration(minutes: 5)),
      bpm: 63,
    ),
  ],
);
final workoutSeries = HeartRateSeriesEntry(
  id: 'whr-series',
  start: from,
  end: to,
  samples: [HeartRateEntry(id: 'whr', at: from, bpm: 150)],
);
final run = WorkoutEntry(
  id: 'run',
  start: from,
  end: to,
  activityType: 'running',
  distanceMeters: 5000.4,
  activeKilocalories: 300.6,
  heartRateSeries: [workoutSeries],
  route: [RoutePoint(at: from, latitude: 1, longitude: 2)],
);

void main() {
  late FakeGateway gateway;
  late FakeSleepSessions sleep;
  late FakeHeartRateSeries heartRate;

  setUp(() {
    gateway = FakeGateway();
    sleep = FakeSleepSessions(gateway.calls);
    heartRate = FakeHeartRateSeries(gateway.calls);
  });

  group('Health Connect', () {
    PluginHealthWriter writer() => PluginHealthWriter(
      gateway,
      HealthPlatform.healthConnect,
      sleepSessions: sleep,
      heartRateSeries: heartRate,
    );

    test('samples upsert by client id and version with no delete', () async {
      await writer().replace(batch(HealthRecordKind.spo2, [spo2]));
      await writer().replace(batch(HealthRecordKind.hrv, [hrv]));

      expect(gateway.calls, everyElement(startsWith('write')));
      expect(gateway.writes, [
        (HealthDataType.BLOOD_OXYGEN, 97.0, 'spo2', 42),
        (HealthDataType.HEART_RATE_VARIABILITY_RMSSD, 55.0, 'hrv', 42),
      ]);
    });

    test(
      'sleep clears the range, then writes one session with every stage',
      () async {
        await writer().replace(batch(HealthRecordKind.sleep, [night]));

        expect(gateway.calls, [
          'sleep delete 1-5',
          'sleep write night 2 stages',
        ]);
        expect(gateway.writes, isEmpty);
        final (session, version) = sleep.written.single;
        expect(session.stages.map((s) => s.stage), [
          SleepStage.light,
          SleepStage.rem,
        ]);
        expect(version, 42);
      },
    );

    test('a re-sent night keeps its id and carries the new version', () async {
      await writer().replace(batch(HealthRecordKind.sleep, [night]));
      await writer().replace(
        HealthWriteBatch(
          kind: HealthRecordKind.sleep,
          from: from,
          to: to,
          version: 43,
          entries: [night],
        ),
      );

      expect(sleep.written.map((w) => (w.$1.id, w.$2)), [
        ('night', 42),
        ('night', 43),
      ]);
      expect(
        gateway.calls.where((c) => c.startsWith('sleep delete')),
        hasLength(2),
      );
    });

    test('a workout clears its session and distance, never energy', () async {
      await writer().replace(batch(HealthRecordKind.workout, [run]));

      expect(gateway.calls, [
        'delete WORKOUT 1-5',
        'delete DISTANCE_DELTA 1-5',
        'hr delete 1-5',
        'workout RUNNING null 5000',
        'hr write 1 series',
        'route uuid-1 1',
      ]);
      expect(gateway.writes, isEmpty);
      final (series, version, active) = heartRate.written.single;
      expect(series, [workoutSeries]);
      expect(version, 42);
      expect(active, isTrue);
    });

    test(
      'a workout without HR keeps the ring HR in its window intact',
      () async {
        final bare = WorkoutEntry(
          id: 'bare',
          start: from,
          end: to,
          activityType: 'walking',
        );

        await writer().replace(batch(HealthRecordKind.workout, [bare]));

        expect(gateway.calls, isNot(contains('hr delete 1-5')));
      },
    );

    test('ring HR clears the range, then goes out as series', () async {
      await writer().replace(batch(HealthRecordKind.heartRate, [hourSeries]));

      expect(gateway.calls, ['hr delete 1-5', 'hr write 1 series']);
      expect(gateway.writes, isEmpty);
      final (series, version, active) = heartRate.written.single;
      expect(series, [hourSeries]);
      expect(version, 42);
      expect(active, isFalse);
    });

    test('sleep, HR and workouts are never deferred to a later run', () async {
      for (final kind in [
        HealthRecordKind.sleep,
        HealthRecordKind.heartRate,
        HealthRecordKind.workout,
      ]) {
        expect(await writer().access(kind), HealthAccess.granted);
      }
    });

    test('access checks the write types and reports a missing app', () async {
      final health = writer();

      expect(
        await health.access(HealthRecordKind.activity),
        HealthAccess.granted,
      );
      expect(gateway.checked, [
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
      ]);
      gateway.granted = false;
      expect(await health.access(HealthRecordKind.sleep), HealthAccess.denied);
      gateway.isAvailable = false;
      expect(
        await health.access(HealthRecordKind.sleep),
        HealthAccess.unavailable,
      );
    });

    test('a refused write raises so the outbox retries it', () async {
      gateway.writeSucceeds = false;

      await expectLater(
        writer().replace(batch(HealthRecordKind.spo2, [spo2])),
        throwsA(isA<HealthWriteException>()),
      );
    });
  });

  group('HealthKit', () {
    PluginHealthWriter writer() => PluginHealthWriter(
      gateway,
      HealthPlatform.healthKit,
      sleepSessions: sleep,
      heartRateSeries: heartRate,
    );

    test('ring HR stays one sample per write after a range delete', () async {
      await writer().replace(batch(HealthRecordKind.heartRate, [hourSeries]));

      expect(gateway.calls, [
        'delete HEART_RATE 1-5',
        'write HEART_RATE',
        'write HEART_RATE',
      ]);
      expect(gateway.writes.map((w) => (w.$2, w.$3)), [
        (61.0, 'hr-1a'),
        (63.0, 'hr-1b'),
      ]);
      expect(heartRate.written, isEmpty);
      expect(
        await writer().access(HealthRecordKind.heartRate),
        HealthAccess.granted,
      );
    });

    test('samples replace the range: delete, then write', () async {
      await writer().replace(batch(HealthRecordKind.spo2, [spo2]));

      expect(gateway.calls, ['delete BLOOD_OXYGEN 1-5', 'write BLOOD_OXYGEN']);
      expect(gateway.writes.single.$2, closeTo(0.97, 1e-9));
    });

    test('HRV goes to SDNN, the only HRV type HealthKit has', () async {
      await writer().replace(batch(HealthRecordKind.hrv, [hrv]));

      expect(
        gateway.writes.single.$1,
        HealthDataType.HEART_RATE_VARIABILITY_SDNN,
      );
    });

    test('sleep writes the in-bed span and then each stage', () async {
      await writer().replace(batch(HealthRecordKind.sleep, [night]));

      expect(gateway.calls, [
        'delete SLEEP_IN_BED 1-5',
        'write SLEEP_IN_BED',
        'write SLEEP_LIGHT',
        'write SLEEP_REM',
      ]);
      expect(gateway.writes.map((w) => w.$3), ['night', 'light', 'rem']);
      expect(sleep.written, isEmpty);
      expect(
        await writer().access(HealthRecordKind.sleep),
        HealthAccess.granted,
      );
    });

    test(
      'a workout clears route and HR in its window and keeps energy',
      () async {
        await writer().replace(batch(HealthRecordKind.workout, [run]));

        expect(gateway.calls, [
          'delete WORKOUT 1-5',
          'delete WORKOUT_ROUTE 1-5',
          'delete HEART_RATE 1-5',
          'workout RUNNING 301 5000',
          'write HEART_RATE',
          'route uuid-1 1',
        ]);
      },
    );
  });

  test('activity types map to a type both platforms accept', () {
    expect(
      [
        'Running',
        'walking',
        'cycling',
        'hiking',
        'rowing',
      ].map(PluginHealthWriter.workoutActivityType),
      [
        HealthWorkoutActivityType.RUNNING,
        HealthWorkoutActivityType.WALKING,
        HealthWorkoutActivityType.BIKING,
        HealthWorkoutActivityType.HIKING,
        HealthWorkoutActivityType.OTHER,
      ],
    );
  });
}
