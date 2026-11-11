import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/domain/sync_scheduler.dart';
import 'package:open_ring/features/ring/infrastructure/workmanager_sync_scheduler.dart';
import 'package:workmanager/workmanager.dart';

typedef Registration = ({
  String uniqueName,
  String taskName,
  Duration? frequency,
  Duration? initialDelay,
  Constraints? constraints,
  ExistingPeriodicWorkPolicy? policy,
});

class FakeWorkmanager implements Workmanager {
  int initializations = 0;
  final registrations = <Registration>[];
  final cancelled = <String>[];

  @override
  Future<void> initialize(
    Function callbackDispatcher, {
    bool isInDebugMode = false,
  }) async => initializations++;

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    ForegroundServiceConfig? foregroundServiceConfig,
  }) async {
    expect(foregroundServiceConfig, isNull);
    registrations.add((
      uniqueName: uniqueName,
      taskName: taskName,
      frequency: frequency,
      initialDelay: initialDelay,
      constraints: constraints,
      policy: existingWorkPolicy,
    ));
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async =>
      cancelled.add(uniqueName);

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void dispatcher() {}

void main() {
  late FakeWorkmanager workmanager;

  setUp(() => workmanager = FakeWorkmanager());

  group('Android', () {
    test('registers one periodic job at the chosen interval', () async {
      final scheduler = AndroidSyncScheduler(dispatcher, workmanager);

      await scheduler.schedule(SyncInterval.minutes60);

      final registration = workmanager.registrations.single;
      expect(registration.uniqueName, ringSyncTaskId);
      expect(registration.frequency, const Duration(minutes: 60));
      expect(registration.policy, ExistingPeriodicWorkPolicy.keep);
    });

    test('needs no network but a battery that is not low', () async {
      await AndroidSyncScheduler(
        dispatcher,
        workmanager,
      ).schedule(SyncInterval.minutes15);

      final constraints = workmanager.registrations.single.constraints;
      expect(constraints?.networkType, NetworkType.notRequired);
      expect(constraints?.requiresBatteryNotLow, isTrue);
      expect(constraints?.requiresCharging, isNot(isTrue));
    });

    test('a changed interval updates the existing job', () async {
      await AndroidSyncScheduler(
        dispatcher,
        workmanager,
      ).schedule(SyncInterval.minutes120, existing: ExistingSchedule.replace);

      expect(
        workmanager.registrations.single.policy,
        ExistingPeriodicWorkPolicy.update,
      );
    });

    test('initializes the plugin once across schedules', () async {
      final scheduler = AndroidSyncScheduler(dispatcher, workmanager);

      await scheduler.schedule(SyncInterval.minutes60);
      await scheduler.schedule(SyncInterval.minutes30);

      expect(workmanager.initializations, 1);
      expect(workmanager.registrations, hasLength(2));
    });

    test('cancel removes the job by its unique name', () async {
      await AndroidSyncScheduler(dispatcher, workmanager).cancel();

      expect(workmanager.cancelled, [ringSyncTaskId]);
    });
  });

  group('iOS', () {
    test('submits the Info.plist identifier with the interval as its '
        'earliest start', () async {
      await IosSyncScheduler(
        dispatcher,
        workmanager,
      ).schedule(SyncInterval.minutes30);

      final registration = workmanager.registrations.single;
      expect(registration.uniqueName, 'gbs.openring.app.sync');
      expect(registration.taskName, 'gbs.openring.app.sync');
      expect(registration.initialDelay, const Duration(minutes: 30));
    });

    test('the identifier is permitted in Info.plist and registered at '
        'launch', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

      expect(plist, contains('<string>$ringSyncTaskId</string>'));
      expect(delegate, contains('withIdentifier: "$ringSyncTaskId"'));
    });
  });
}
