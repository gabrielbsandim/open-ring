import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:open_ring/app/background/background_sync_runner.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_read_store.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/health_sync/infrastructure/method_channel_heart_rate_series.dart';
import 'package:open_ring/features/health_sync/infrastructure/method_channel_sleep_sessions.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_writer.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_store.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../helpers/database.dart';
import '../../helpers/fake_health_reader.dart';
import '../../helpers/fake_health_writer.dart';
import '../../helpers/fake_ring_driver.dart';
import '../../helpers/sync_fixtures.dart';

const Duration lockTimeout = SyncPairedRing.defaultLockTimeout;

BackgroundSyncRunner runner(AppDatabase db, FakeRingDriver driver) =>
    BackgroundSyncRunner(database: db, driver: driver, clock: () => syncNow);

final class ConnectGateway implements HealthGateway {
  final workouts = <HealthWorkoutActivityType>[];

  @override
  Future<bool> available() async => true;

  @override
  Future<bool> hasWriteAccess(List<HealthDataType> types) async => true;

  @override
  Future<bool> requestWriteAccess(List<HealthDataType> types) async => true;

  @override
  Future<bool> write(
    HealthDataType type,
    double value, {
    required DateTime start,
    required DateTime end,
    required String clientRecordId,
    required int version,
  }) async => true;

  @override
  Future<bool> delete(
    HealthDataType type, {
    required DateTime from,
    required DateTime to,
  }) async => true;

  @override
  Future<String?> writeWorkout({
    required HealthWorkoutActivityType type,
    required DateTime start,
    required DateTime end,
    int? kilocalories,
    int? meters,
  }) async {
    workouts.add(type);
    return 'workout-1';
  }

  @override
  Future<bool> writeRoute(
    String workoutId,
    List<WorkoutRouteLocation> route,
  ) async => true;
}

Future<void> saveWorkout(AppDatabase db, DateTime start) {
  final session = WorkoutSession(
    type: WorkoutType.running,
    profile: const WorkoutProfile(weightKilograms: 70),
  )..start(start);
  for (var s = 0; s < 10; s++) {
    session.addHeartRate(140 + s, start.add(Duration(seconds: s)));
  }
  session.finish(start.add(const Duration(minutes: 20)));
  return DriftWorkoutStore(db)
      .save(session.finished(), at: start.add(const Duration(minutes: 21)));
}

List<MethodCall> recordChannel(String name) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final channel = MethodChannel(name);
  final calls = <MethodCall>[];
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return calls;
}

final class HungConnectDriver extends FakeRingDriver {
  @override
  Future<void> connect(String deviceId) {
    calls.add('connect');
    return Completer<void>().future;
  }
}

final class HungHealthWriter implements HealthWriter {
  @override
  Future<HealthAccess> access(HealthRecordKind kind) =>
      Completer<HealthAccess>().future;

  @override
  Future<bool> requestAccess(Set<HealthRecordKind> kinds) async => true;

  @override
  Future<void> replace(HealthWriteBatch batch) async {}
}

void main() {
  group('timeout', () {
    const short = Duration(milliseconds: 20);

    test('a hung ring call releases the lock and disconnects', () async {
      final db = await pairedDatabase();
      final driver = HungConnectDriver();

      final outcome = await BackgroundSyncRunner(
        database: db,
        driver: driver,
        clock: () => syncNow,
        timeout: short,
      ).run();

      expect(outcome, isA<SyncFailed>());
      expect(driver.disconnects, 1);
      expect(await SyncLocksDao(db).current(), isNull);
    });

    test('a hung health write keeps the completed ring sync', () async {
      final db = await pairedDatabase();
      final driver = loadedDriver();

      final outcome = await BackgroundSyncRunner(
        database: db,
        driver: driver,
        healthWriter: HungHealthWriter(),
        clock: () => syncNow,
        timeout: const Duration(milliseconds: 200),
      ).run();

      expect(outcome, isA<SyncCompleted>());
      expect(await rowCount(db, 'hr_samples'), nightHeartRate.length);
      expect(await SyncLocksDao(db).current(), isNull);
    });

    test('a timed out run is logged so the failure streak sees it', () async {
      final db = await pairedDatabase();
      final store = DriftSyncStore(db);

      await BackgroundSyncRunner(
        database: db,
        driver: HungConnectDriver(),
        clock: () => syncNow,
        timeout: short,
      ).run();

      final ring = await store.pairedRing();
      final runs = await store.recentRuns(ring!.deviceId);
      expect(runs, hasLength(1));
      expect(runs.single.failed, isTrue);
    });

    test('the default budget stays inside the worker limit and lease', () {
      const lease = SyncPairedRing.defaultLockTimeout;

      expect(BackgroundSyncRunner.defaultTimeout, lessThan(lease));
      expect(
        BackgroundSyncRunner.defaultTimeout +
            BackgroundSyncRunner.defaultCleanupTimeout * 3 +
            defaultBackgroundAlertTimeout +
            defaultBackgroundStepTimeout * 3,
        lessThan(lease),
      );
    });
  });

  group('superviseBackgroundSync', () {
    const short = Duration(milliseconds: 10);

    test('keeps the process alive first and survives a hung start', () async {
      final order = <String>[];

      final reported = await superviseBackgroundSync(
        keepAlive: () {
          order.add('keepAlive');
          return Completer<void>().future;
        },
        sync: () async => order.add('sync'),
        sendAlerts: () async {},
        publishWidgets: () async {},
        announceFinished: () {},
        teardown: [() async => order.add('stop')],
        stepTimeout: short,
        alertTimeout: short,
      );

      expect(reported, isTrue);
      expect(order, ['keepAlive', 'sync', 'stop']);
    });

    test('without a paired ring the sync runs with no service', () async {
      final order = <String>[];

      await superviseBackgroundSync(
        ringPaired: () async => false,
        keepAlive: () async => order.add('keepAlive'),
        sync: () async => order.add('sync'),
        sendAlerts: () async {},
        publishWidgets: () async {},
        announceFinished: () {},
        teardown: [() async => order.add('stop')],
        stepTimeout: short,
        alertTimeout: short,
      );

      expect(order, ['sync', 'stop']);
    });

    test('a ring check that fails still keeps the process alive', () async {
      final order = <String>[];

      await superviseBackgroundSync(
        ringPaired: () => Future<bool>.error(StateError('database closed')),
        keepAlive: () async => order.add('keepAlive'),
        sync: () async => order.add('sync'),
        sendAlerts: () async {},
        publishWidgets: () async {},
        announceFinished: () {},
        teardown: [() async => order.add('stop')],
        stepTimeout: short,
        alertTimeout: short,
      );

      expect(order, ['keepAlive', 'sync', 'stop']);
    });

    test('a demo skips the sync and still tears down', () async {
      final order = <String>[];

      final reported = await superviseBackgroundSync(
        demoMode: () async => true,
        keepAlive: () async => order.add('keepAlive'),
        sync: () async => order.add('sync'),
        sendAlerts: () async => order.add('alerts'),
        publishWidgets: () async => order.add('widgets'),
        announceFinished: () => order.add('announced'),
        teardown: [() async => order.add('stop')],
        stepTimeout: short,
        alertTimeout: short,
      );

      expect(reported, isTrue);
      expect(order, ['stop']);
    });

    test('an unreadable demo flag still syncs', () async {
      final order = <String>[];

      await superviseBackgroundSync(
        demoMode: () async => throw StateError('no preferences'),
        sync: () async => order.add('sync'),
        sendAlerts: () async {},
        publishWidgets: () async {},
        announceFinished: () {},
        teardown: const [],
        stepTimeout: short,
        alertTimeout: short,
      );

      expect(order, ['sync']);
    });

    test('answers even when every step hangs or throws', () async {
      final finished = <String>[];

      final reported = await superviseBackgroundSync(
        sync: () async => throw StateError('no database'),
        sendAlerts: () => Completer<void>().future,
        publishWidgets: () => Completer<void>().future,
        announceFinished: () => finished.add('announced'),
        teardown: [
          () => Completer<void>().future,
          () async => finished.add('closed'),
        ],
        stepTimeout: short,
        alertTimeout: short,
      );

      expect(reported, isTrue);
      expect(finished, ['announced', 'closed']);
    });

    test('a throwing alert step keeps the result and the next steps', () async {
      final order = <String>[];

      final reported = await superviseBackgroundSync(
        sync: () async => order.add('sync'),
        sendAlerts: () async => throw StateError('notifications down'),
        publishWidgets: () async => order.add('widgets'),
        announceFinished: () => order.add('announced'),
        teardown: [() async => order.add('closed')],
        stepTimeout: short,
        alertTimeout: short,
      );

      expect(reported, isTrue);
      expect(order, ['sync', 'announced', 'widgets', 'closed']);
    });

    test('a hung alert step is cut off at its own limit', () async {
      final order = <String>[];

      final reported = await superviseBackgroundSync(
        sync: () async {},
        sendAlerts: () => Completer<void>().future,
        publishWidgets: () async => order.add('widgets'),
        announceFinished: () {},
        teardown: const [],
        alertTimeout: short,
      ).timeout(const Duration(seconds: 2));

      expect(reported, isTrue);
      expect(order, ['widgets']);
    });

    test('announces once the sync is done, before the teardown', () async {
      final order = <String>[];

      await superviseBackgroundSync(
        sync: () async => order.add('sync'),
        sendAlerts: () async => order.add('alerts'),
        publishWidgets: () async => order.add('widgets'),
        announceFinished: () => order.add('announced'),
        teardown: [() async => order.add('closed')],
        stepTimeout: short,
        alertTimeout: short,
      );

      expect(order, ['sync', 'announced', 'alerts', 'widgets', 'closed']);
    });
  });

  test('syncs the paired ring and releases the lock', () async {
    final db = await pairedDatabase();
    final driver = loadedDriver();

    final outcome = await runner(db, driver).run();

    expect(outcome, isA<SyncCompleted>());
    expect(driver.connects, 1);
    expect(driver.disconnects, 1);
    expect(await rowCount(db, 'hr_samples'), nightHeartRate.length);
    expect(await SyncLocksDao(db).current(), isNull);
  });

  test('with no paired ring it returns without touching the ring', () async {
    final db = memoryDatabase();
    final driver = loadedDriver();

    final outcome = await runner(db, driver).run();

    expect(outcome, isA<NothingPaired>());
    expect(driver.calls, isEmpty);
    expect(await SyncLocksDao(db).current(), isNull);
  });

  test('skips while another sync holds the lock', () async {
    final db = await pairedDatabase();
    final driver = loadedDriver();
    await SyncLocksDao(db).acquire(
      'foreground',
      at: syncNow.subtract(const Duration(minutes: 2)),
      timeout: lockTimeout,
    );

    final outcome = await runner(db, driver).run();

    expect(outcome, isA<AlreadySyncing>());
    expect(driver.calls, isEmpty);
    expect((await SyncLocksDao(db).current())?.owner, 'foreground');
  });

  test('two overlapping runs connect to the ring once', () async {
    final db = await pairedDatabase();
    final first = loadedDriver();
    final second = loadedDriver();

    final outcomes = await Future.wait([
      runner(db, first).run(),
      runner(db, second).run(),
    ]);

    expect(outcomes.whereType<SyncCompleted>(), hasLength(1));
    expect(outcomes.whereType<AlreadySyncing>(), hasLength(1));
    expect(first.connects + second.connects, 1);
  });

  test('takes over a stale lock left by a killed run', () async {
    final db = await pairedDatabase();
    final driver = loadedDriver();
    await SyncLocksDao(db).acquire(
      'killed',
      at: syncNow.subtract(lockTimeout),
      timeout: lockTimeout,
    );

    final outcome = await runner(db, driver).run();

    expect(outcome, isA<SyncCompleted>());
    expect(driver.connects, 1);
    expect(await SyncLocksDao(db).current(), isNull);
  });

  test('a failed sync still releases the lock', () async {
    final db = await pairedDatabase();
    final driver = loadedDriver()
      ..connectError = const BleTransportException('out of range');

    final outcome = await runner(db, driver).run();

    expect(outcome, isA<SyncFailed>());
    expect(await SyncLocksDao(db).current(), isNull);
  });

  test('writes the outbox to the health platform after the sync', () async {
    final db = await pairedDatabase();
    final writer = FakeHealthWriter();

    final outcome = await BackgroundSyncRunner(
      database: db,
      driver: loadedDriver(),
      healthWriter: writer,
      clock: () => syncNow,
    ).run();

    expect(outcome, isA<SyncCompleted>());
    expect(writer.entriesOf(HealthRecordKind.heartRate), hasLength(3));
    expect(await HealthOutboxDao(db).pending(), isEmpty);
  });

  test('a background run sends heart rate, workout and sleep rows', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final db = await pairedDatabase();
    await saveWorkout(db, syncNow.subtract(const Duration(hours: 2)));
    final sleep = recordChannel(MethodChannelSleepSessions.channelName);
    final heartRate = recordChannel(MethodChannelHeartRateSeries.channelName);
    final gateway = ConnectGateway();

    final outcome = await BackgroundSyncRunner(
      database: db,
      driver: loadedDriver(),
      healthWriter: PluginHealthWriter(
        gateway,
        HealthPlatform.healthConnect,
        sleepSessions: const MethodChannelSleepSessions(),
        heartRateSeries: const MethodChannelHeartRateSeries(),
      ),
      clock: () => syncNow,
    ).run();

    expect(outcome, isA<SyncCompleted>());
    expect(sleep.where((c) => c.method == 'write'), hasLength(1));
    final activeFlags = [
      for (final call in heartRate)
        if (call.method == 'write')
          (call.arguments as Map<Object?, Object?>)['active'],
    ];
    expect(activeFlags, containsAll([false, true]));
    expect(gateway.workouts, [HealthWorkoutActivityType.RUNNING]);
    expect(
      (await HealthOutboxDao(db).all()).map((row) => row.status),
      everyElement(isIn([OutboxStatus.done, OutboxStatus.notApplicable])),
    );
  });

  test('a health platform error never fails the ring sync', () async {
    final db = await pairedDatabase();
    final writer = FakeHealthWriter()..failuresLeft = 100;

    final outcome = await BackgroundSyncRunner(
      database: db,
      driver: loadedDriver(),
      healthWriter: writer,
      clock: () => syncNow,
    ).run();

    expect(outcome, isA<SyncCompleted>());
    expect(await rowCount(db, 'hr_samples'), nightHeartRate.length);
    expect(
      (await HealthOutboxDao(db).pending()).map((r) => r.attempts),
      everyElement(lessThanOrEqualTo(1)),
    );
  });

  test('imports other sleep even when the ring is out of range', () async {
    final db = await pairedDatabase();
    await DriftHealthReadStore(db)
        .setEnabled(HealthRecordKind.sleep, enabled: true);
    final reader = FakeHealthReader(
      access: HealthAccess.granted,
      nights: [
        externalNight(
          'com.garmin.android.apps.connectmobile',
          syncNow.subtract(const Duration(hours: 9)),
        ),
      ],
    );
    final driver = loadedDriver()
      ..connectError = const BleTransportException('out of range');

    final outcome = await BackgroundSyncRunner(
      database: db,
      driver: driver,
      healthReader: reader,
      clock: () => syncNow,
    ).run();

    expect(outcome, isA<SyncFailed>());
    expect(await rowCount(db, 'imported_sleep_sessions'), 1);
    expect(await rowCount(db, 'health_outbox'), 0);
  });

  test('a background engine without read access imports nothing', () async {
    final db = await pairedDatabase();
    await DriftHealthReadStore(db)
        .setEnabled(HealthRecordKind.sleep, enabled: true);
    final reader = FakeHealthReader(access: HealthAccess.deferred);

    await BackgroundSyncRunner(
      database: db,
      driver: loadedDriver(),
      healthReader: reader,
      clock: () => syncNow,
    ).run();

    expect(reader.reads, isEmpty);
    expect(await rowCount(db, 'imported_sleep_sessions'), 0);
  });
}
