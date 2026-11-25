import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/food/application/food_energy_gate.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/domain/food_energy_store.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/application/goals_data.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/infrastructure/drift_goal_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

import '../../../helpers/database.dart';
import '../../goals/goal_fixtures.dart';

const _today = LocalDate(2026, 11, 24);
const Set<ModuleId> _modules = {ModuleId.ai, ModuleId.food, ModuleId.body};
const _adult = UserProfile(
  birthYear: 1990,
  sex: Sex.female,
  heightCentimeters: 168,
);

GoalScreening _screening(int day, {bool? soft, bool? pregnant}) =>
    GoalScreening(
      on: LocalDate(2026, 11, day),
      softMode: soft,
      pregnantOrBreastfeeding: pregnant,
    );

final class _Setup {
  new({
    Set<ModuleId> modules = _modules,
    UserProfile? profile = _adult,
    List<GoalScreening> screenings = const [],
    bool demo = false,
    WeightSummary? weight,
    FoodEnergyOptIn? optIn,
    GoalStore? goalStore,
  }) : goals = goalStore ?? InMemoryGoalStore(),
       store = InMemoryFoodEnergyStore(optIn),
       demoStore = InMemoryDemoModeStore(enabled: demo) {
    screenings.forEach(goals.addScreening);
    container = ProviderContainer.test(
      overrides: [
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 24, 12)),
        moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
        demoModeStoreProvider.overrideWithValue(demoStore),
        userProfileStoreProvider.overrideWithValue(
          InMemoryUserProfileStore(profile),
        ),
        goalStoreProvider.overrideWithValue(goals),
        weightSummaryProvider.overrideWith((ref) async => weight),
        foodEnergyStoreProvider.overrideWithValue(store),
      ],
    );
  }

  final GoalStore goals;
  final InMemoryFoodEnergyStore store;
  final InMemoryDemoModeStore demoStore;
  late final ProviderContainer container;

  Future<FoodEnergyGate> gate() async {
    await container.read(enabledModulesProvider.future);
    return await container.read(foodEnergyGateProvider.future);
  }

  FoodEnergyOptInController get controller =>
      container.read(foodEnergyOptInControllerProvider.notifier);

  Future<void> screen({required bool soft, int day = 25}) async {
    await goals.addScreening(_screening(day, soft: soft));
    container.read(dataRevisionProvider.notifier).bump();
  }
}

Matcher _blocked(FoodEnergyBlock block) =>
    isA<FoodEnergyBlocked>().having((gate) => gate.block, 'block', block);

void main() {
  group('hidden and demo come first', () {
    for (final modules in [
      {ModuleId.food, ModuleId.body},
      {ModuleId.ai, ModuleId.body},
    ]) {
      test('$modules is hidden', () async {
        final setup = _Setup(modules: modules, demo: true);

        expect(await setup.gate(), isA<FoodEnergyHidden>());
      });
    }

    test('demo mode wins over every block', () async {
      final setup = _Setup(modules: {ModuleId.ai, ModuleId.food}, demo: true);

      expect(await setup.gate(), isA<FoodEnergyDemo>());
    });
  });

  group('each block reason, in its order', () {
    final cases = <(String, _Setup Function(), FoodEnergyBlock)>[
      (
        'Body off before soft mode',
        () => _Setup(
          modules: {ModuleId.ai, ModuleId.food},
          screenings: [_screening(1, soft: true)],
        ),
        FoodEnergyBlock.bodyOff,
      ),
      (
        'soft mode before a missing age',
        () => _Setup(
          profile: const UserProfile(heightCentimeters: 168),
          screenings: [_screening(1, soft: true)],
        ),
        FoodEnergyBlock.softMode,
      ),
      (
        'a missing age',
        () => _Setup(profile: const UserProfile(heightCentimeters: 168)),
        FoodEnergyBlock.ageMissing,
      ),
      (
        'under 18 before a missing height',
        () => _Setup(profile: const UserProfile(birthYear: 2010)),
        FoodEnergyBlock.under18,
      ),
      (
        'a missing height before pregnancy',
        () => _Setup(
          profile: const UserProfile(birthYear: 1990),
          screenings: [_screening(1, pregnant: true)],
        ),
        FoodEnergyBlock.heightMissing,
      ),
      (
        'a BMI under the floor before pregnancy',
        () => _Setup(
          profile: const UserProfile(
            birthYear: 1990,
            sex: Sex.female,
            heightCentimeters: 210,
          ),
          weight: goalWeightSummary(),
          screenings: [_screening(1, pregnant: true)],
        ),
        FoodEnergyBlock.bmiUnderFloor,
      ),
      (
        'pregnancy before a missing sex',
        () => _Setup(
          profile: const UserProfile(birthYear: 1990, heightCentimeters: 168),
          screenings: [_screening(1, pregnant: true)],
        ),
        FoodEnergyBlock.pregnancy,
      ),
      (
        'a missing sex before the screening',
        () => _Setup(
          profile: const UserProfile(birthYear: 1990, heightCentimeters: 168),
        ),
        FoodEnergyBlock.sexMissing,
      ),
    ];
    for (final (name, setup, block) in cases) {
      test(name, () async {
        expect(await setup().gate(), _blocked(block));
      });
    }

    test('a stored pregnancy no does not block', () async {
      final setup = _Setup(
        screenings: [
          _screening(1, pregnant: false),
          _screening(2, soft: false),
        ],
      );

      expect(await setup.gate(), isA<FoodEnergyOffered>());
    });
  });

  test('no screening yet needs one', () async {
    expect(await _Setup().gate(), isA<FoodEnergyNeedsScreening>());
  });

  test('offered names the newest screening that asked the questions', () async {
    final setup = _Setup(
      screenings: [
        _screening(3, soft: true),
        _screening(10, soft: false),
        _screening(12, pregnant: false),
      ],
    );

    expect(
      await setup.gate(),
      isA<FoodEnergyOffered>().having(
        (gate) => gate.screenedOn,
        'screenedOn',
        const LocalDate(2026, 11, 10),
      ),
    );
  });

  group('the opt in', () {
    test('turnOn from offered stores today and the soft count, and the '
        'gate is on', () async {
      final setup = _Setup(
        screenings: [_screening(3, soft: true), _screening(10, soft: false)],
      );
      await setup.gate();

      expect(await setup.controller.turnOn(), isTrue);

      expect(setup.store.optIn, (
        on: _today,
        soft: (id: 1, on: const LocalDate(2026, 11, 3)),
      ));
      expect(
        await setup.gate(),
        isA<FoodEnergyOn>().having((gate) => gate.since, 'since', _today),
      );
      expect(setup.container.read(mealPhotoItemsEnabledProvider), isTrue);
    });

    test('a new soft mode screening blocks, and leaving soft mode offers '
        'again, never on', () async {
      final setup = _Setup(screenings: [_screening(10, soft: false)]);
      await setup.gate();
      await setup.controller.turnOn();

      await setup.screen(soft: true);

      expect(await setup.gate(), _blocked(FoodEnergyBlock.softMode));
      expect(setup.container.read(mealPhotoItemsEnabledProvider), isFalse);
      expect(setup.store.optIn, isNotNull);

      await setup.screen(soft: false, day: 26);

      expect(await setup.gate(), isA<FoodEnergyOffered>());
      expect(setup.container.read(mealPhotoItemsEnabledProvider), isFalse);
    });

    test('a Goals wipe, a new soft screening and leaving soft mode never '
        'turn it back on', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final setup = _Setup(goalStore: DriftGoalStore(db));
      await setup.screen(soft: true, day: 3);
      await setup.screen(soft: false, day: 10);
      expect(await setup.gate(), isA<FoodEnergyOffered>());
      expect(await setup.controller.turnOn(), isTrue);
      expect(await setup.gate(), isA<FoodEnergyOn>());

      await setup.goals.clear();
      setup.container.read(dataRevisionProvider.notifier).bump();
      await setup.screen(soft: true, day: 3);
      await setup.screen(soft: false, day: 10);

      expect(await setup.gate(), isA<FoodEnergyOffered>());
    });

    test(
      'a stored opt in naming another soft screening reads offered',
      () async {
        final setup = _Setup(
          screenings: [_screening(10, soft: false)],
          optIn: (on: _today, soft: (id: 9, on: const LocalDate(2026, 11, 1))),
        );

        expect(await setup.gate(), isA<FoodEnergyOffered>());
      },
    );

    test('turnOn writes nothing unless the gate offers it', () async {
      for (final setup in [
        _Setup(),
        _Setup(modules: {ModuleId.ai, ModuleId.food}),
        _Setup(demo: true, screenings: [_screening(10, soft: false)]),
      ]) {
        await setup.gate();

        expect(await setup.controller.turnOn(), isFalse);
        expect(setup.store.optIn, isNull);
      }
    });

    test('turnOn is false in demo mode even once demo starts late', () async {
      final setup = _Setup(screenings: [_screening(10, soft: false)]);
      expect(await setup.gate(), isA<FoodEnergyOffered>());
      setup.demoStore.enabled = true;
      setup.container.invalidate(demoModeProvider);

      expect(await setup.controller.turnOn(), isFalse);
      expect(setup.store.optIn, isNull);
    });

    test('an opt in with no soft row, then soft mode, a Goals wipe and '
        'leaving soft mode reads offered', () async {
      final setup = _Setup(screenings: [_screening(10, soft: false)]);
      expect(await setup.gate(), isA<FoodEnergyOffered>());
      expect(await setup.controller.turnOn(), isTrue);
      expect(setup.store.optIn?.soft, isNull);

      await setup.screen(soft: true, day: 20);
      expect(
        await setup.container.read(goalsDataEraserProvider).clear(),
        isTrue,
      );
      await setup.screen(soft: false, day: 21);

      expect(await setup.gate(), isA<FoodEnergyOffered>());
      expect(setup.store.optIn, isNull);
    });

    test('turnOff removes the opt in and the gate offers it again', () async {
      final setup = _Setup(
        screenings: [_screening(10, soft: false)],
        optIn: (on: _today, soft: null),
      );
      expect(await setup.gate(), isA<FoodEnergyOn>());

      await setup.controller.turnOff();

      expect(setup.store.optIn, isNull);
      expect(await setup.gate(), isA<FoodEnergyOffered>());
    });

    test('AI off hides it and keeps the opt in', () async {
      final setup = _Setup(
        modules: {ModuleId.food, ModuleId.body},
        screenings: [_screening(10, soft: false)],
        optIn: (on: _today, soft: null),
      );

      expect(await setup.gate(), isA<FoodEnergyHidden>());
      expect(setup.store.optIn, isNotNull);
    });
  });

  test('items are off while the gate loads', () {
    final setup = _Setup(
      screenings: [_screening(10, soft: false)],
      optIn: (on: _today, soft: null),
    );

    expect(setup.container.read(mealPhotoItemsEnabledProvider), isFalse);
  });
}
