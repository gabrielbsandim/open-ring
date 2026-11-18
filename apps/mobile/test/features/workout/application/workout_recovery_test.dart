import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_data.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_notice.dart';
import 'package:open_ring/features/workout/application/workout_recovery.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/domain/workout_recovery.dart';
import 'package:open_ring/features/workout/infrastructure/drift_open_workout_store.dart';
import 'package:open_ring/features/workout/infrastructure/isolate_live_workout_registry.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/database.dart';
import '../../../helpers/open_workout_fakes.dart';

final launchAt = DateTime.utc(2026, 11, 10, 12);

final WorkoutNoticeLabels enLabels = workoutLocationNotice(
  lookupAppLocalizations(const Locale('en')),
).live;

void main() {
  late AppDatabase db;
  late InMemoryWorkoutNotifier notifier;
  late InMemoryLiveWorkoutRegistry registry;

  setUp(() {
    db = memoryDatabase();
    notifier = InMemoryWorkoutNotifier();
    registry = InMemoryLiveWorkoutRegistry();
  });

  ProviderContainer container({
    UnitSystem units = UnitSystem.metric,
    bool demo = false,
    LiveWorkoutRegistry? live,
  }) {
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(() => launchAt),
        openWorkoutStoreProvider.overrideWithValue(DriftOpenWorkoutStore(db)),
        liveWorkoutRegistryProvider.overrideWithValue(live ?? registry),
        workoutNotifierProvider.overrideWithValue(notifier),
        workoutRecoveryLabelsProvider.overrideWithValue(enLabels),
        unitSystemStoreProvider.overrideWithValue(
          InMemoryUnitSystemStore(units),
        ),
        demoModeStoreProvider.overrideWithValue(
          InMemoryDemoModeStore(enabled: demo),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<RecoveredWorkout?> recover(ProviderContainer c) async {
    await c.read(workoutRecoveryProvider.notifier).run();
    return c.read<RecoveredWorkout?>(workoutRecoveryProvider);
  }

  test('the in memory registry marks, reports and clears a start', () async {
    expect(await registry.isLive(openStart), isFalse);
    registry.markLive(openStart);
    expect(await registry.isLive(openStart), isTrue);
    expect(await registry.isLive(openStartAfter(1)), isFalse);
    registry.clear(openStart);
    expect(await registry.isLive(openStart), isFalse);
  });

  test('criterion 1: an open row is closed, queued once and announced with '
      'a link to its summary', () async {
    final id = await insertOpenRow(db);

    final recovered = await recover(container());

    expect(recovered!.id, id);
    final row = await rowOf(db, id);
    expect(row.endUtcMs, isNotNull);
    expect(row.checkpointUtcMs, isNull);
    expect(await rowCount(db, 'health_outbox'), 1);
    expect(notifier.endedNotices, hasLength(1));
    final notice = notifier.endedNotices.single;
    expect(notice.title, 'Workout saved until 07:31');
    expect(notice.link, '$workoutSummaryLink/$id');
    expect(notice.failed, isFalse);
  });

  for (final demo in [false, true]) {
    test('criterion 2: a demo open row is closed with 0 outbox rows, demo '
        'mode $demo', () async {
      final id = await insertOpenRow(db, deviceId: demoDeviceId);
      final c = container(demo: demo);
      expect(c.read(demoModeProvider), demo);

      await recover(c);

      expect((await rowOf(db, id)).endUtcMs, isNotNull);
      expect(await rowCount(db, 'health_outbox'), 0);
    });
  }

  test('criterion 3: a start that is live stays open with no notice and no '
      'outbox row', () async {
    final id = await insertOpenRow(db);
    registry.markLive(openStart);

    final recovered = await recover(container());

    expect(recovered, isNull);
    final row = await rowOf(db, id);
    expect(row.endUtcMs, isNull);
    expect(row.checkpointUtcMs, isNotNull);
    expect(notifier.endedNotices, isEmpty);
    expect(await rowCount(db, 'health_outbox'), 0);
  });

  test('criterion 3: only the live start is skipped, the other closes and '
      'is announced', () async {
    final liveId = await insertOpenRow(db, start: openStartAfter(1));
    final deadId = await insertOpenRow(db);
    registry.markLive(openStartAfter(1));

    final recovered = await recover(container());

    expect((await rowOf(db, liveId)).endUtcMs, isNull);
    expect((await rowOf(db, deadId)).endUtcMs, isNotNull);
    expect(recovered!.id, deadId);
    expect(notifier.endedNotices.single.link, '$workoutSummaryLink/$deadId');
    expect(await rowCount(db, 'health_outbox'), 1);
  });

  test('a process wide mark whose isolate died does not keep the row '
      'open', () async {
    final id = await insertOpenRow(db);
    final dead = ReceivePort();
    IsolateNameServer.registerPortWithName(
      dead.sendPort,
      'openring.workout.live.${openStart.millisecondsSinceEpoch}',
    );
    dead.close();
    final live = IsolateLiveWorkoutRegistry();
    addTearDown(() => live.clear(openStart));

    final recovered = await recover(container(live: live));

    expect(recovered!.id, id);
    expect((await rowOf(db, id)).endUtcMs, isNotNull);
    expect(notifier.endedNotices, hasLength(1));
  });

  test('a process wide mark that answers keeps the row open', () async {
    final id = await insertOpenRow(db);
    final live = IsolateLiveWorkoutRegistry()..markLive(openStart);
    addTearDown(() => live.clear(openStart));

    final recovered = await recover(container(live: live));

    expect(recovered, isNull);
    expect((await rowOf(db, id)).endUtcMs, isNull);
    expect(notifier.endedNotices, isEmpty);
  });

  test('criterion 4: a finished row is untouched and gets no notice', () async {
    final id = await insertFinishedRow(db, start: openStart);
    final before = await rowOf(db, id);

    final recovered = await recover(container());

    expect(recovered, isNull);
    expect(await rowOf(db, id), before);
    expect(notifier.endedNotices, isEmpty);
    expect(await rowCount(db, 'health_outbox'), 0);
  });

  test('criterion 4: running twice closes once and posts one notice', () async {
    await insertOpenRow(db);
    final c = container();
    final recovery = c.read(workoutRecoveryProvider.notifier);

    await recovery.run();
    await recovery.run();

    expect(await rowCount(db, 'health_outbox'), 1);
    expect(notifier.endedNotices, hasLength(1));
  });

  test('criterion 4: a row that opens after the first run is not closed by '
      'the second', () async {
    await insertOpenRow(db);
    final c = container();
    await c.read(workoutRecoveryProvider.notifier).run();
    final later = await insertOpenRow(db, start: openStartAfter(2));

    await c.read(workoutRecoveryProvider.notifier).run();

    expect((await rowOf(db, later)).endUtcMs, isNull);
    expect(notifier.endedNotices, hasLength(1));
  });

  test('criterion 5: two open rows both close and one notice is posted, for '
      'the newer', () async {
    final olderId = await insertOpenRow(db);
    final newerId = await insertOpenRow(db, start: openStartAfter(1));

    final recovered = await recover(container());

    expect((await rowOf(db, olderId)).endUtcMs, isNotNull);
    expect((await rowOf(db, newerId)).endUtcMs, isNotNull);
    expect(await rowCount(db, 'health_outbox'), 2);
    expect(recovered!.id, newerId);
    expect(notifier.endedNotices, hasLength(1));
    expect(notifier.endedNotices.single.link, '$workoutSummaryLink/$newerId');
    expect(notifier.endedNotices.single.title, 'Workout saved until 08:31');
  });

  test('criterion 7: when the notifier throws the rows are still closed and '
      'run completes', () async {
    final id = await insertOpenRow(db);
    notifier.failing = true;

    await recover(container());

    expect((await rowOf(db, id)).endUtcMs, isNotNull);
    expect(await rowCount(db, 'health_outbox'), 1);
    expect(notifier.endedNotices, isEmpty);
  });

  test(
    'imperial units show mi even when they were still loading at launch',
    () async {
      await insertOpenRow(db);

      await recover(container(units: UnitSystem.imperial));

      expect(notifier.endedNotices.single.text, contains('1.86 mi'));
    },
  );

  test(
    'closing a row bumps the data revision so Today and history refresh',
    () async {
      await insertOpenRow(db);
      final c = container();
      final before = c.read(dataRevisionProvider);

      await recover(c);

      expect(c.read(dataRevisionProvider), greaterThan(before));
    },
  );

  test('with no open row nothing is posted and the revision stays', () async {
    final c = container();

    final recovered = await recover(c);

    expect(recovered, isNull);
    expect(notifier.endedNotices, isEmpty);
    expect(c.read(dataRevisionProvider), 0);
  });
}
