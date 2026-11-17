import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/goals/application/goal_review_trigger.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';

import '../../../helpers/ring_fakes.dart';
import '../goal_fixtures.dart';

DateTime _monday(int hour, int minute) => DateTime(2026, 12, 7, hour, minute);

final class _Calls {
  final log = <String>[];
  final errors = <Object>[];
  bool enabled = true;
  bool mayReview = true;
  int starts = 0;
  int reviews = 0;
  int startFailures = 0;
  int reviewFailures = 0;
  bool mayReviewFails = false;
  Future<void> Function(int call)? onStart;
  Future<void> Function(int call)? onReview;

  late final GoalReviewTrigger trigger = GoalReviewTrigger(
    enabled: () => enabled,
    startDueBlock: () async {
      starts++;
      log.add('start');
      await onStart?.call(starts);
      if (startFailures > 0) {
        startFailures--;
        throw StateError('start');
      }
      return false;
    },
    mayReview: () async {
      log.add('mayReview');
      if (mayReviewFails) throw StateError('mayReview');
      return mayReview;
    },
    reviewDueWeek: () async {
      reviews++;
      log.add('review');
      await onReview?.call(reviews);
      if (reviewFailures > 0) {
        reviewFailures--;
        throw StateError('review');
      }
      return null;
    },
    onError: errors.add,
  );
}

final class _SpyStore implements GoalStore {
  new(this.inner, {this.onActive});

  final InMemoryGoalStore inner;
  final Future<void> Function()? onActive;
  int weeksReads = 0;

  @override
  Future<Goal?> active() async {
    await onActive?.call();
    return await inner.active();
  }

  @override
  Future<List<GoalWeek>> weeks(int goalId) {
    weeksReads++;
    return inner.weeks(goalId);
  }

  @override
  Future<List<GoalScreening>> screenings() => inner.screenings();

  @override
  Future<bool> addWeek(
    int goalId, {
    required LocalDate monday,
    required ReviewInputs inputs,
    required Review review,
  }) => inner.addWeek(goalId, monday: monday, inputs: inputs, review: review);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('the store was read: ${invocation.memberName}');
}

final class _SlowModuleStore implements ModuleStore {
  final gate = Completer<Set<ModuleId>>();

  @override
  Future<Set<ModuleId>> read() => gate.future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('the module store was written');
}

List<String> _capturedDebugPrint() {
  final original = debugPrint;
  final logs = <String>[];
  debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  addTearDown(() => debugPrint = original);
  return logs;
}

Future<void> _settle() => pumpEventQueue(times: 100);

Future<GoalSetup> _rig({
  DateTime? now,
  DateTime Function()? clockOf,
  Set<ModuleId> modules = goalModules,
  ModuleStore? moduleStore,
  bool settleModules = true,
  GoalDraft? draft,
  InMemoryGoalStore? store,
  GoalStore? readStore,
  FakeSyncStore? sync,
}) => setupGoals(
  now: now,
  clockOf: clockOf,
  modules: modules,
  moduleStore: moduleStore,
  settleModules: settleModules,
  draft: draft ?? goalDraft(),
  store: store,
  readStore: readStore,
  extraOverrides: [
    syncStoreProvider.overrideWithValue(sync ?? FakeSyncStore()),
  ],
);

void _startTrigger(GoalSetup setup) =>
    setup.container.listen(goalReviewTriggerProvider, (_, _) {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('case 4: a Monday with no ring sync', () {
    test('the review may not run', () {
      expect(reviewMayRun(now: _monday(8, 10), lastSyncAt: null), isFalse);
    });
  });

  group('case 5: a Monday waits for a sync at or after local midnight', () {
    test('a sync at 23:59 the day before does not count', () {
      final lastSyncAt = DateTime(2026, 12, 6, 23, 59);

      expect(
        reviewMayRun(now: _monday(8, 10), lastSyncAt: lastSyncAt),
        isFalse,
      );
    });

    test('a sync at 00:00 counts', () {
      final lastSyncAt = DateTime(2026, 12, 7);

      expect(reviewMayRun(now: _monday(8, 10), lastSyncAt: lastSyncAt), isTrue);
    });

    test('a sync at 06:00 counts', () {
      final lastSyncAt = _monday(6, 0);

      expect(reviewMayRun(now: _monday(8, 10), lastSyncAt: lastSyncAt), isTrue);
    });

    test('a sync a week old does not count', () {
      final lastSyncAt = DateTime(2026, 11, 30, 9);

      expect(
        reviewMayRun(now: _monday(8, 10), lastSyncAt: lastSyncAt),
        isFalse,
      );
    });

    test('the same edge holds for an instant in UTC', () {
      final now = DateTime.utc(2026, 12, 7, 8, 10);

      expect(
        reviewMayRun(now: now, lastSyncAt: DateTime.utc(2026, 12, 6, 23, 59)),
        isFalse,
      );
      expect(
        reviewMayRun(now: now, lastSyncAt: DateTime.utc(2026, 12, 7)),
        isTrue,
      );
    });
  });

  group('case 6: any other day needs no sync', () {
    test('a Tuesday with no ring may run', () {
      expect(
        reviewMayRun(now: DateTime(2026, 12, 8, 8, 10), lastSyncAt: null),
        isTrue,
      );
    });

    test('a Sunday with no ring may run', () {
      expect(
        reviewMayRun(now: DateTime(2026, 12, 13, 8, 10), lastSyncAt: null),
        isTrue,
      );
    });
  });

  group('case 7: a pass with Goals off', () {
    test('calls nothing', () async {
      final calls = _Calls()..enabled = false;

      await calls.trigger.run();

      expect(calls.log, isEmpty);
      expect(calls.errors, isEmpty);
    });
  });

  group('case 8: a review that may not run', () {
    test('starts the block once and never reviews', () async {
      final calls = _Calls()..mayReview = false;

      await calls.trigger.run();

      expect(calls.starts, 1);
      expect(calls.reviews, 0);
    });
  });

  group('case 9: the order of a pass', () {
    test('is start, mayReview, review', () async {
      final calls = _Calls();

      await calls.trigger.run();

      expect(calls.log, ['start', 'mayReview', 'review']);
    });
  });

  group('case 10: a run during a pass', () {
    test(
      'three runs while the start waits make 2 passes, never at once',
      () async {
        final calls = _Calls();
        final gate = Completer<void>();
        calls.onStart = (call) => call == 1 ? gate.future : Future.value();

        unawaited(calls.trigger.run());
        unawaited(calls.trigger.run());
        unawaited(calls.trigger.run());
        await pumpEventQueue();
        expect(calls.log, ['start']);

        gate.complete();
        await pumpEventQueue();

        expect(calls.log, [
          'start',
          'mayReview',
          'review',
          'start',
          'mayReview',
          'review',
        ]);
      },
    );

    test('a run after the pass ended starts a fresh pass', () async {
      final calls = _Calls();

      await calls.trigger.run();
      await calls.trigger.run();

      expect(calls.starts, 2);
      expect(calls.reviews, 2);
    });
  });

  group('case 11: a start that throws', () {
    test('is reported once and the review still runs', () async {
      final calls = _Calls()..startFailures = 1;

      await expectLater(calls.trigger.run(), completes);

      expect(calls.errors, hasLength(1));
      expect(calls.errors.single, isA<StateError>());
      expect(calls.reviews, 1);
    });

    test('a mayReview that throws is reported and the review does not '
        'run', () async {
      final calls = _Calls()..mayReviewFails = true;

      await expectLater(calls.trigger.run(), completes);

      expect(calls.errors, hasLength(1));
      expect(calls.reviews, 0);
    });
  });

  group('case 12: a review that throws', () {
    test('is reported once and a later run calls it again', () async {
      final calls = _Calls()..reviewFailures = 1;

      await expectLater(calls.trigger.run(), completes);
      expect(calls.errors, hasLength(1));
      expect(calls.reviews, 1);

      await calls.trigger.run();

      expect(calls.reviews, 2);
      expect(calls.errors, hasLength(1));
    });
  });

  group('review focus 2: a bump that arrives during a pass', () {
    test('during the start step gives exactly one rerun', () async {
      final calls = _Calls();
      calls.onStart = (call) async {
        if (call == 1) unawaited(calls.trigger.run());
      };

      await calls.trigger.run();
      await pumpEventQueue();

      expect(calls.log, [
        'start',
        'mayReview',
        'review',
        'start',
        'mayReview',
        'review',
      ]);
    });

    test('during the review step gives exactly one rerun', () async {
      final calls = _Calls();
      calls.onReview = (call) async {
        if (call == 1) unawaited(calls.trigger.run());
      };

      await calls.trigger.run();
      await pumpEventQueue();

      expect(calls.starts, 2);
      expect(calls.reviews, 2);
    });
  });

  group('case 13: the provider on a Tuesday with no ring', () {
    test('writes one row, bumps once and ends after one empty '
        'pass', () async {
      final memory = InMemoryGoalStore();
      final spy = _SpyStore(memory);
      final setup = await _rig(
        now: goalAt(12, 8),
        draft: goalDraft(),
        store: memory,
        readStore: spy,
      );

      _startTrigger(setup);
      await _settle();

      final weeks = await setup.weeks();
      expect([for (final week in weeks) week.monday], [goalDay(12, 7)]);
      expect(setup.revision, 1);
      expect(spy.weeksReads, 2);

      await _settle();
      expect(spy.weeksReads, 2);
      expect(setup.revision, 1);
    });
  });

  group('case 14: the provider on a Monday', () {
    test('waits with no ring, then reviews after a sync and a bump', () async {
      final sync = FakeSyncStore();
      final setup = await _rig(now: goalAt(12, 7), sync: sync);
      _startTrigger(setup);
      await _settle();
      expect(await setup.weeks(), isEmpty);
      expect(setup.revision, 0);

      sync.ring = PairedRing(deviceId: fakeRingId, lastSyncAt: _monday(6, 0));
      setup.container.read(dataRevisionProvider.notifier).bump();
      await _settle();

      expect(await setup.weeks(), hasLength(1));
      expect(setup.revision, 2);
    });
  });

  group('case 15: the provider across midnight', () {
    test('a Monday review waiting for no sync runs on the Tuesday', () async {
      var now = goalAt(12, 7);
      final setup = await _rig(clockOf: () => now);
      _startTrigger(setup);
      await _settle();
      expect(await setup.weeks(), isEmpty);

      now = goalAt(12, 8);
      setup.container.read(dayRollProvider).check();
      await _settle();

      final weeks = await setup.weeks();
      expect([for (final week in weeks) week.monday], [goalDay(12, 7)]);
    });
  });

  group('case 16: the provider with Goals off', () {
    test('never reads the goal store', () async {
      final logs = _capturedDebugPrint();
      final setup = await _rig(
        modules: const {ModuleId.body},
        readStore: UnreadableGoalStore(),
      );

      _startTrigger(setup);
      await _settle();

      expect(logs, isEmpty);
      expect(setup.revision, 0);
      expect(await setup.weeks(), isEmpty);
    });
  });

  group('case 17: the provider while the modules load', () {
    test('runs a pass once Goals turns on', () async {
      final modules = _SlowModuleStore();
      final setup = await _rig(
        now: goalAt(12, 8),
        moduleStore: modules,
        settleModules: false,
      );
      _startTrigger(setup);
      await _settle();
      expect(await setup.weeks(), isEmpty);
      expect(setup.revision, 0);

      modules.gate.complete(goalModules);
      await _settle();

      final weeks = await setup.weeks();
      expect([for (final week in weeks) week.monday], [goalDay(12, 7)]);
      expect(setup.revision, 1);
    });
  });

  group('review focus 3: the date is checked before it is read', () {
    test('the first store read of a pass sees the rolled date', () async {
      var now = goalAt(12, 13, 23, 50);
      final seen = <LocalDate>[];
      final memory = InMemoryGoalStore();
      late GoalSetup setup;
      final spy = _SpyStore(
        memory,
        onActive: () async =>
            seen.add(setup.container.read(currentDateProvider)),
      );
      final sync = FakeSyncStore(
        ring: PairedRing(
          deviceId: fakeRingId,
          lastSyncAt: DateTime(2026, 12, 14, 0, 5),
        ),
      );
      setup = await _rig(
        clockOf: () => now,
        draft: goalDraft(kind: GoalKind.getFitter, startedOn: goalDay(12, 1)),
        store: memory,
        readStore: spy,
        sync: sync,
      );
      _startTrigger(setup);
      await _settle();
      expect(await setup.weeks(), isEmpty);

      seen.clear();
      now = goalAt(12, 14, 0);
      setup.container.read(dataRevisionProvider.notifier).bump();
      await _settle();

      expect(seen.first, goalDay(12, 14));
      final weeks = await setup.weeks();
      expect([for (final week in weeks) week.monday], [goalDay(12, 14)]);
    });
  });

  group('review focus 5: a container disposed mid pass', () {
    test('reads nothing after the dispose and reports nothing', () async {
      final logs = _capturedDebugPrint();
      final gate = Completer<void>();
      final memory = InMemoryGoalStore();
      final spy = _SpyStore(memory, onActive: () => gate.future);
      final setup = await _rig(
        now: goalAt(12, 8),
        store: memory,
        readStore: spy,
      );
      _startTrigger(setup);
      await pumpEventQueue();

      setup.container.dispose();
      gate.complete();
      await _settle();

      expect(logs, isEmpty);
    });
  });

  group('case 11 at the edge: a store that throws', () {
    test('is logged, the container survives and a later bump runs a '
        'pass', () async {
      final logs = _capturedDebugPrint();
      var failing = true;
      final memory = InMemoryGoalStore();
      final spy = _SpyStore(
        memory,
        onActive: () async {
          if (failing) throw StateError('the store failed');
        },
      );
      final setup = await _rig(
        now: goalAt(12, 8),
        store: memory,
        readStore: spy,
      );

      _startTrigger(setup);
      await _settle();
      expect(logs, isNotEmpty);
      expect(await setup.weeks(), isEmpty);

      failing = false;
      setup.container.read(dataRevisionProvider.notifier).bump();
      await _settle();

      expect(await setup.weeks(), hasLength(1));
    });
  });
}
