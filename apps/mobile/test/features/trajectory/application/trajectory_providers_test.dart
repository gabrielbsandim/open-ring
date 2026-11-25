import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/domain/weigh_in_store.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_data.dart';
import 'package:open_ring/features/demo/domain/demo_data_store.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/domain/onboarding_store.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/in_memory_projection_store.dart';
import 'package:open_ring/features/trajectory/domain/projection_store.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';

const _monday = LocalDate(2026, 11, 23);
const _wednesday = LocalDate(2026, 11, 25);
const _sunday = LocalDate(2026, 11, 22);
const _firstDay = LocalDate(2026, 10, 20);
const Set<ModuleId> _bodyAndTrajectory = {ModuleId.body, ModuleId.trajectory};
const _adult = UserProfile(birthYear: 1990, heightCentimeters: 175);

// The same instant is Sunday 23:30 at -03:00 and Monday 08:30 at +09:00.
final _instant = DateTime.utc(2026, 11, 23, 2, 30);

final class _SpyStore implements ProjectionStore {
  new(this.inner, {this.failInsert = false});

  final InMemoryProjectionStore inner;
  final bool failInsert;
  int deleteCalls = 0;

  @override
  Future<bool> insertIfAbsent(TrajectoryProjection projection) {
    if (failInsert) throw StateError('insert failed');
    return inner.insertIfAbsent(projection);
  }

  @override
  Future<List<TrajectoryProjection>> all() => inner.all();

  @override
  Future<int> deleteAll() {
    deleteCalls++;
    return inner.deleteAll();
  }
}

final class _GatedProfileStore implements UserProfileStore {
  final gate = Completer<UserProfile?>();

  @override
  Future<UserProfile?> read() => gate.future;

  @override
  Future<void> save(UserProfile profile, {required DateTime at}) async {}
}

final class _WipingDemoStore implements DemoDataStore {
  new(this.weighIns);

  final InMemoryWeighInStore weighIns;

  @override
  Future<void> replace(DemoData data) async {}

  @override
  Future<void> wipe() async {
    await weighIns.deleteAll();
  }
}

final class _SlowOnboardingStore implements OnboardingStore {
  @override
  bool completed = true;

  @override
  Future<void> complete() async {}

  @override
  Future<void> reset() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    completed = false;
  }
}

WeighInDraft _draft(
  LocalDate day,
  double kilograms, {
  WeighInSource source = WeighInSource.manual,
}) => WeighInDraft(
  at: DateTime.utc(day.year, day.month, day.day, 8),
  offsetMinutes: 0,
  kilograms: kilograms,
  source: source,
);

List<WeighInDraft> _series({
  LocalDate from = _firstDay,
  LocalDate to = _wednesday,
  double start = 80,
  double perDay = -0.05,
  double wobble = 0.3,
  double shift = 0,
  WeighInSource source = WeighInSource.manual,
}) => [
  for (var i = 0; from.addDays(i).compareTo(to) <= 0; i++)
    _draft(
      from.addDays(i),
      start + shift + perDay * i + (i.isEven ? wobble : -wobble),
      source: source,
    ),
];

Future<InMemoryWeighInStore> _weighIns(List<WeighInDraft> drafts) async {
  final store = InMemoryWeighInStore();
  for (final draft in drafts) {
    await store.add(draft);
  }
  return store;
}

Future<ProviderContainer> _open({
  required ProjectionStore store,
  InMemoryWeighInStore? weighIns,
  Set<ModuleId> modules = _bodyAndTrajectory,
  UserProfileStore? profileStore,
  UserProfile? profile = _adult,
  InMemoryGoalStore? goals,
  LocalDate today = _wednesday,
  bool demo = false,
  bool hidden = false,
  List<Override> extra = const [],
}) async {
  final seeded = weighIns ?? await _weighIns(_series(to: today));
  final container = ProviderContainer.test(
    overrides: [
      projectionStoreProvider.overrideWithValue(store),
      weighInStoreProvider.overrideWithValue(seeded),
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      userProfileStoreProvider.overrideWithValue(
        profileStore ?? InMemoryUserProfileStore(profile),
      ),
      goalStoreProvider.overrideWithValue(goals ?? InMemoryGoalStore()),
      demoModeStoreProvider.overrideWithValue(
        InMemoryDemoModeStore(enabled: demo),
      ),
      numbersHiddenProvider.overrideWithValue(hidden),
      clockProvider.overrideWithValue(() => _instant),
      currentDateProvider.overrideWithValue(today),
      ...extra,
    ],
  );
  return container;
}

Future<TrajectoryView> _view(ProviderContainer container) =>
    container.read(trajectoryViewProvider.future);

Future<List<TrajectoryProjection>> _rows(ProjectionStore store) => store.all();

void main() {
  group('trajectoryViewProvider', () {
    test('1. Trajectory off gives Off and 0 rows', () async {
      final store = InMemoryProjectionStore();
      final container = await _open(
        store: store,
        modules: const {ModuleId.body},
      );

      expect(await _view(container), isA<TrajectoryOff>());
      expect(await _rows(store), isEmpty);
    });

    test('1. Body off gives Off and 0 rows', () async {
      final store = InMemoryProjectionStore();
      final container = await _open(
        store: store,
        modules: const {ModuleId.trajectory},
      );

      expect(await _view(container), isA<TrajectoryOff>());
      expect(await _rows(store), isEmpty);
    });

    test('2. Underage gives Refused(underage) and 0 rows', () async {
      final store = InMemoryProjectionStore();
      final container = await _open(
        store: store,
        profile: const UserProfile(birthYear: 2011, heightCentimeters: 160),
      );

      final view = await _view(container);

      expect(view, isA<TrajectoryRefused>());
      expect((view as TrajectoryRefused).reason, TrajectoryRefusal.underage);
      expect(await _rows(store), isEmpty);
    });

    test('2. Newest pregnancy true gives Refused(pregnancy), 0 rows', () async {
      final store = InMemoryProjectionStore();
      final goals = InMemoryGoalStore();
      await goals.addScreening(
        const GoalScreening(
          on: LocalDate(2026, 9, 1),
          softMode: null,
          pregnantOrBreastfeeding: false,
        ),
      );
      await goals.addScreening(
        const GoalScreening(
          on: LocalDate(2026, 11, 1),
          softMode: null,
          pregnantOrBreastfeeding: true,
        ),
      );
      final container = await _open(store: store, goals: goals);

      final view = await _view(container);

      expect(view, isA<TrajectoryRefused>());
      expect((view as TrajectoryRefused).reason, TrajectoryRefusal.pregnancy);
      expect(await _rows(store), isEmpty);
    });

    test('2. No height gives Refused(noHeight) and 0 rows', () async {
      final store = InMemoryProjectionStore();
      final container = await _open(
        store: store,
        profile: const UserProfile(birthYear: 1990),
      );

      final view = await _view(container);

      expect(view, isA<TrajectoryRefused>());
      expect((view as TrajectoryRefused).reason, TrajectoryRefusal.noHeight);
      expect(await _rows(store), isEmpty);
    });

    test('2. No profile at all gives Refused(noHeight) and 0 rows', () async {
      final store = InMemoryProjectionStore();
      final container = await _open(store: store, profile: null);

      final view = await _view(container);

      expect(view, isA<TrajectoryRefused>());
      expect((view as TrajectoryRefused).reason, TrajectoryRefusal.noHeight);
      expect(await _rows(store), isEmpty);
    });

    test('3. Pregnancy answer null does not refuse', () async {
      final store = InMemoryProjectionStore();
      final goals = InMemoryGoalStore();
      await goals.addScreening(
        const GoalScreening(
          on: LocalDate(2026, 11, 1),
          softMode: true,
          pregnantOrBreastfeeding: null,
        ),
      );
      final container = await _open(store: store, goals: goals);

      expect(await _view(container), isA<TrajectoryReady>());
    });

    test('3. Pregnancy answer false does not refuse', () async {
      final store = InMemoryProjectionStore();
      final goals = InMemoryGoalStore();
      await goals.addScreening(
        const GoalScreening(
          on: LocalDate(2026, 11, 1),
          softMode: null,
          pregnantOrBreastfeeding: false,
        ),
      );
      final container = await _open(store: store, goals: goals);

      expect(await _view(container), isA<TrajectoryReady>());
    });

    test(
      '3. An older true answer under a newer false does not refuse',
      () async {
        final store = InMemoryProjectionStore();
        final goals = InMemoryGoalStore();
        await goals.addScreening(
          const GoalScreening(
            on: LocalDate(2026, 9, 1),
            softMode: null,
            pregnantOrBreastfeeding: true,
          ),
        );
        await goals.addScreening(
          const GoalScreening(
            on: LocalDate(2026, 11, 1),
            softMode: null,
            pregnantOrBreastfeeding: false,
          ),
        );
        final container = await _open(store: store, goals: goals);

        expect(await _view(container), isA<TrajectoryReady>());
      },
    );

    test('4. No weigh-ins gives Building(null) and 0 rows', () async {
      final store = InMemoryProjectionStore();
      final container = await _open(
        store: store,
        weighIns: await _weighIns(const []),
      );

      final view = await _view(container);

      expect(view, isA<TrajectoryBuilding>());
      expect((view as TrajectoryBuilding).rate, isNull);
      expect(await _rows(store), isEmpty);
    });

    test('4. 5 weigh-ins give Building with the rate missing counts', () async {
      final store = InMemoryProjectionStore();
      final container = await _open(
        store: store,
        weighIns: await _weighIns(_series(from: const LocalDate(2026, 11, 21))),
      );

      final view = await _view(container);

      expect(view, isA<TrajectoryBuilding>());
      final rate = (view as TrajectoryBuilding).rate;
      expect(rate, isNotNull);
      expect(rate!.daysMissing, 3);
      expect(rate.spanMissing, 10);
      expect(await _rows(store), isEmpty);
    });

    test('5. percentLow above 1 gives Guard and 0 rows', () async {
      final store = InMemoryProjectionStore();
      final container = await _open(
        store: store,
        weighIns: await _weighIns(_series(start: 100, perDay: -1, wobble: 0.1)),
      );

      final view = await _view(container);

      expect(view, isA<TrajectoryGuard>());
      expect((view as TrajectoryGuard).loss.percentLow, greaterThan(1));
      expect(await _rows(store), isEmpty);
    });

    test('6. Ready stores one row keyed by the Monday with the band', () async {
      final store = InMemoryProjectionStore();
      final drafts = _series();
      final container = await _open(
        store: store,
        weighIns: await _weighIns(drafts),
      );
      final daily = dailyWeights([
        for (final draft in drafts)
          (
            date: LocalDate.fromInstant(draft.at, Duration.zero),
            value: draft.kilograms,
          ),
      ]);
      final past = [
        for (final day in daily)
          if (day.date.compareTo(_monday) <= 0) day,
      ];
      final trend = weightTrend(past).last.value;
      final rate = weightRate(past, today: _monday) as WeightRateReady;
      final band = weightScenario(
        trend,
        rate,
        weightNoise(past),
        trajectoryFirmDays,
      );

      final view = await _view(container);
      final rows = await _rows(store);

      expect(view, isA<TrajectoryReady>());
      expect((view as TrajectoryReady).asOf, _wednesday);
      expect(view.firm.days, trajectoryFirmDays);
      expect(rows, hasLength(1));
      expect(rows.single.monday, _monday);
      expect(rows.single.lowKg, closeTo(band.low, 1e-9));
      expect(rows.single.midKg, closeTo(band.mid, 1e-9));
      expect(rows.single.highKg, closeTo(band.high, 1e-9));
    });

    test(
      '7. A second open with other weigh-ins keeps the first values',
      () async {
        final store = InMemoryProjectionStore();
        final first = await _open(store: store);
        await _view(first);
        final before = (await _rows(store)).single;

        final second = await _open(
          store: store,
          weighIns: await _weighIns(_series(shift: 6, perDay: -0.1)),
        );
        await _view(second);
        final rows = await _rows(store);

        expect(rows, hasLength(1));
        expect(rows.single.lowKg, before.lowKg);
        expect(rows.single.midKg, before.midKg);
        expect(rows.single.highKg, before.highKg);
        expect(rows.single.trendKg, before.trendKg);
      },
    );

    test(
      '7. A weigh-in back-dated to the Monday keeps the first row',
      () async {
        final store = InMemoryProjectionStore();
        final weighIns = await _weighIns(_series());
        final container = await _open(store: store, weighIns: weighIns);
        await _view(container);
        final before = (await _rows(store)).single;

        await weighIns.add(_draft(_monday, 110));
        container.read(dataRevisionProvider.notifier).bump();
        await _view(container);
        final rows = await _rows(store);

        expect(rows, hasLength(1));
        expect(rows.single.midKg, before.midKg);
        expect(rows.single.trendKg, before.trendKg);
      },
    );

    test(
      '8. Sunday 23:30 at -03:00 then +09:00 writes two Mondays once',
      () async {
        final store = InMemoryProjectionStore();
        final weighIns = await _weighIns(_series(to: _sunday));
        final west = await _open(
          store: store,
          weighIns: weighIns,
          today: _sunday,
        );
        await _view(west);
        final east = await _open(
          store: store,
          weighIns: weighIns,
          today: _monday,
        );
        await _view(east);
        await _view(east);

        final rows = await _rows(store);

        expect(rows.map((row) => row.monday), [
          const LocalDate(2026, 11, 16),
          _monday,
        ]);
      },
    );

    test('8. Two zones inside one week write 1 row', () async {
      final store = InMemoryProjectionStore();
      final weighIns = await _weighIns(_series(to: _sunday));
      final tuesday = await _open(
        store: store,
        weighIns: weighIns,
        today: const LocalDate(2026, 11, 24),
      );
      await _view(tuesday);
      final friday = await _open(
        store: store,
        weighIns: weighIns,
        today: const LocalDate(2026, 11, 27),
      );
      await _view(friday);

      final rows = await _rows(store);

      expect(rows, hasLength(1));
      expect(rows.single.monday, _monday);
    });

    test('9. Hidden numbers true or false gives equal rows', () async {
      final shown = InMemoryProjectionStore();
      final hiddenStore = InMemoryProjectionStore();
      await _view(await _open(store: shown));
      await _view(await _open(store: hiddenStore, hidden: true));

      final a = (await _rows(shown)).single;
      final b = (await _rows(hiddenStore)).single;

      expect(b.monday, a.monday);
      expect(b.trendKg, a.trendKg);
      expect(b.rateKgPerWeek, a.rateKgPerWeek);
      expect(b.lowKg, a.lowKg);
      expect(b.midKg, a.midKg);
      expect(b.highKg, a.highKg);
    });

    test('10. Demo mode stores 0 rows', () async {
      final store = InMemoryProjectionStore();
      final container = await _open(store: store, demo: true);

      final view = await _view(container);

      expect(view, isNot(isA<TrajectoryError>()));
      expect(await _rows(store), isEmpty);
    });

    test('Leaving demo mode stores no band from demo weigh-ins', () async {
      final store = InMemoryProjectionStore();
      final weighIns = await _weighIns(_series(source: WeighInSource.demo));
      final container = await _open(
        store: store,
        weighIns: weighIns,
        demo: true,
        extra: [
          demoDataStoreProvider.overrideWithValue(_WipingDemoStore(weighIns)),
          onboardingStoreProvider.overrideWithValue(_SlowOnboardingStore()),
        ],
      );
      final subscription = container.listen(
        trajectoryViewProvider,
        (previous, next) {},
      );
      addTearDown(subscription.close);
      await _view(container);

      final left = await container.read(demoModeProvider.notifier).leave();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(left, isTrue);
      expect(container.read(demoModeProvider), isFalse);
      expect(await _rows(store), isEmpty);
    });

    test('A band is never stored from demo weigh-ins', () async {
      final store = InMemoryProjectionStore();
      final container = await _open(
        store: store,
        weighIns: await _weighIns(_series(source: WeighInSource.demo)),
      );

      final view = await _view(container);

      expect(view, isA<TrajectoryReady>());
      expect(await _rows(store), isEmpty);
    });

    test('11. A throwing read gives Error and deletes nothing', () async {
      final inner = InMemoryProjectionStore();
      await inner.insertIfAbsent(
        TrajectoryProjection(
          monday: const LocalDate(2026, 11, 9),
          trendKg: 81,
          rateKgPerWeek: -0.3,
          lowKg: 79,
          midKg: 79.5,
          highKg: 80,
          createdAt: DateTime.utc(2026, 11, 9, 8),
        ),
      );
      final store = _SpyStore(inner);
      final container = await _open(
        store: store,
        extra: [
          weighInsProvider.overrideWith(
            (ref) => throw StateError('read failed'),
          ),
        ],
      );

      final view = await _view(container);

      expect(view, isA<TrajectoryError>());
      expect((view as TrajectoryError).error, isA<StateError>());
      expect(store.deleteCalls, 0);
      expect(await _rows(store), hasLength(1));
    });

    test('11. A throwing insert still gives Ready and is logged', () async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = original);
      final store = _SpyStore(InMemoryProjectionStore(), failInsert: true);
      final container = await _open(store: store);

      final view = await _view(container);

      expect(view, isA<TrajectoryReady>());
      expect(logs, isNotEmpty);
      expect(store.deleteCalls, 0);
    });

    test('12. No row for any Monday before the current one', () async {
      final store = InMemoryProjectionStore();
      final container = await _open(
        store: store,
        weighIns: await _weighIns(_series(from: const LocalDate(2026, 8, 1))),
      );

      await _view(container);
      final rows = await _rows(store);

      expect(rows, hasLength(1));
      expect(rows.single.monday, _monday);
    });

    test(
      'Ready today with a building Monday snapshot writes nothing',
      () async {
        final store = InMemoryProjectionStore();
        final container = await _open(
          store: store,
          weighIns: await _weighIns(
            _series(from: const LocalDate(2026, 11, 11)),
          ),
        );

        final view = await _view(container);

        expect(view, isA<TrajectoryReady>());
        expect(await _rows(store), isEmpty);
      },
    );

    test(
      'Underage null while the profile loads is awaited, not adult',
      () async {
        final store = InMemoryProjectionStore();
        final gated = _GatedProfileStore();
        final container = await _open(store: store, profileStore: gated);
        var settled = false;
        final pending = _view(container).whenComplete(() => settled = true);

        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(settled, isFalse);
        expect(await _rows(store), isEmpty);

        gated.gate.complete(
          const UserProfile(birthYear: 2011, heightCentimeters: 160),
        );
        final view = await pending;

        expect(view, isA<TrajectoryRefused>());
        expect((view as TrajectoryRefused).reason, TrajectoryRefusal.underage);
        expect(await _rows(store), isEmpty);
      },
    );

    test('Recomputes when the data revision changes', () async {
      final store = InMemoryProjectionStore();
      final weighIns = await _weighIns(_series());
      final container = await _open(store: store, weighIns: weighIns);
      final first = await _view(container) as TrajectoryReady;

      await weighIns.add(_draft(_wednesday, 95));
      container.read(dataRevisionProvider.notifier).bump();
      final second = await _view(container) as TrajectoryReady;

      expect(second.trendKg, isNot(first.trendKg));
      expect(await _rows(store), hasLength(1));
    });
  });
}
