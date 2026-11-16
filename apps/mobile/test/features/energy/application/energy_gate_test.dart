import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

final DateTime _now = DateTime.utc(2026, 11, 10, 12);

final class _PendingProfileStore implements UserProfileStore {
  final Completer<UserProfile?> release = Completer<UserProfile?>();

  @override
  Future<UserProfile?> read() => release.future;

  @override
  Future<void> save(UserProfile profile, {required DateTime at}) =>
      throw StateError('the gate never saves');
}

final class _PendingModuleStore implements ModuleStore {
  final Completer<Set<ModuleId>> release = Completer<Set<ModuleId>>();

  @override
  Future<Set<ModuleId>> read() => release.future;

  @override
  Future<void> write(Set<ModuleId> enabled) =>
      throw StateError('the gate never writes');

  @override
  Future<bool> shortcutDismissed() => throw StateError('unused');

  @override
  Future<void> dismissShortcut({required bool dismissed}) =>
      throw StateError('unused');
}

UserProfile _aged(int age) => UserProfile(
  birthYear: UserProfile.birthYearFor(age, year: _now.year),
  sex: Sex.male,
  heightCentimeters: 175,
  weightKilograms: 70,
);

ProviderContainer _container({
  required ModuleStore modules,
  required UserProfileStore profile,
  bool hidden = false,
}) => ProviderContainer.test(
  overrides: [
    clockProvider.overrideWithValue(() => _now),
    moduleStoreProvider.overrideWithValue(modules),
    userProfileStoreProvider.overrideWithValue(profile),
    hideNumbersStoreProvider.overrideWithValue(
      InMemoryHideNumbersStore(hidden: hidden),
    ),
  ],
);

Future<EnergyGate> _gate({
  Set<ModuleId> modules = const {ModuleId.energy},
  UserProfile? profile,
  bool hidden = false,
}) async {
  final container = _container(
    modules: InMemoryModuleStore(modules),
    profile: InMemoryUserProfileStore(profile),
    hidden: hidden,
  );
  await container.read(enabledModulesProvider.future);
  await container.read(userProfileProvider.future);
  await container.read(hideNumbersProvider.future);
  return container.read(energyGateProvider);
}

void main() {
  group('the floor', () {
    test('the row floor is a positive number of kilocalories', () {
      expect(energyRowFloor, greaterThan(0));
    });
  });

  group('the module', () {
    test('is off without the Energy module', () async {
      expect(
        await _gate(modules: const {}, profile: _aged(energyAdultAge)),
        EnergyGate.off,
      );
    });

    test('is off with other modules on but not Energy', () async {
      expect(
        await _gate(
          modules: const {ModuleId.body, ModuleId.openScore},
          profile: _aged(energyAdultAge),
        ),
        EnergyGate.off,
      );
    });

    test('is off while the modules load', () async {
      final modules = _PendingModuleStore();
      final container = _container(
        modules: modules,
        profile: InMemoryUserProfileStore(_aged(energyAdultAge)),
      );

      expect(container.read(energyGateProvider), EnergyGate.off);

      modules.release.complete(const {ModuleId.energy});
      await container.read(enabledModulesProvider.future);
      await container.read(userProfileProvider.future);
      await container.read(hideNumbersProvider.future);

      expect(container.read(energyGateProvider), EnergyGate.on);
    });

    test('is off while the profile loads', () async {
      final profile = _PendingProfileStore();
      final container = _container(
        modules: InMemoryModuleStore(const {ModuleId.energy}),
        profile: profile,
      );
      await container.read(enabledModulesProvider.future);
      await container.read(hideNumbersProvider.future);

      expect(container.read(energyGateProvider), EnergyGate.off);

      profile.release.complete(_aged(energyAdultAge - 1));
      await container.read(userProfileProvider.future);

      expect(container.read(energyGateProvider), EnergyGate.underage);
    });
  });

  group('the age', () {
    test('is underage one year below the adult age', () async {
      expect(
        await _gate(profile: _aged(energyAdultAge - 1)),
        EnergyGate.underage,
      );
    });

    test('is on at the adult age', () async {
      expect(await _gate(profile: _aged(energyAdultAge)), EnergyGate.on);
    });

    test('is on well above the adult age', () async {
      expect(await _gate(profile: _aged(energyAdultAge + 40)), EnergyGate.on);
    });

    test('is on with no profile', () async {
      expect(await _gate(), EnergyGate.on);
    });

    test('is on with a profile that has no birth year', () async {
      expect(
        await _gate(profile: const UserProfile(sex: Sex.female)),
        EnergyGate.on,
      );
    });

    test('counts the age in the year of the clock', () async {
      const born = 2000;
      final container = ProviderContainer.test(
        overrides: [
          clockProvider.overrideWithValue(
            () => DateTime.utc(born + energyAdultAge - 1, 6),
          ),
          moduleStoreProvider.overrideWithValue(
            InMemoryModuleStore(const {ModuleId.energy}),
          ),
          userProfileStoreProvider.overrideWithValue(
            InMemoryUserProfileStore(const UserProfile(birthYear: born)),
          ),
        ],
      );
      await container.read(enabledModulesProvider.future);
      await container.read(userProfileProvider.future);

      expect(container.read(energyGateProvider), EnergyGate.underage);
    });
  });

  group('the hidden numbers', () {
    test('is hidden with Body on and the numbers hidden', () async {
      expect(
        await _gate(
          modules: const {ModuleId.energy, ModuleId.body},
          profile: _aged(energyAdultAge),
          hidden: true,
        ),
        EnergyGate.hidden,
      );
    });

    test('is on with Body on and the numbers shown', () async {
      expect(
        await _gate(
          modules: const {ModuleId.energy, ModuleId.body},
          profile: _aged(energyAdultAge),
        ),
        EnergyGate.on,
      );
    });

    test('is on with Body off even when the hide switch is on', () async {
      expect(
        await _gate(profile: _aged(energyAdultAge), hidden: true),
        EnergyGate.on,
      );
    });

    test('underage wins over hidden', () async {
      expect(
        await _gate(
          modules: const {ModuleId.energy, ModuleId.body},
          profile: _aged(energyAdultAge - 1),
          hidden: true,
        ),
        EnergyGate.underage,
      );
    });

    test('stays hidden until the hide choice is read with Body on', () async {
      final container = _container(
        modules: InMemoryModuleStore(const {ModuleId.energy, ModuleId.body}),
        profile: InMemoryUserProfileStore(_aged(energyAdultAge)),
      );
      await container.read(enabledModulesProvider.future);
      await container.read(userProfileProvider.future);

      expect(container.read(energyGateProvider), EnergyGate.hidden);

      await container.read(hideNumbersProvider.future);

      expect(container.read(energyGateProvider), EnergyGate.on);
    });
  });
}
