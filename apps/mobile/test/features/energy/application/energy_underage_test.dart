import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
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
      throw StateError('the provider never saves');
}

final class _PendingModuleStore implements ModuleStore {
  final Completer<Set<ModuleId>> release = Completer<Set<ModuleId>>();

  @override
  Future<Set<ModuleId>> read() => release.future;

  @override
  Future<void> write(Set<ModuleId> enabled) =>
      throw StateError('the provider never writes');

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
  DateTime? now,
}) => ProviderContainer.test(
  overrides: [
    clockProvider.overrideWithValue(() => now ?? _now),
    moduleStoreProvider.overrideWithValue(modules),
    userProfileStoreProvider.overrideWithValue(profile),
  ],
);

Future<bool?> _underage({UserProfile? profile, DateTime? now}) async {
  final container = _container(
    modules: InMemoryModuleStore(),
    profile: InMemoryUserProfileStore(profile),
    now: now,
  );
  await container.read(userProfileProvider.future);
  final value = container.read(energyUnderageProvider);
  return value;
}

Future<Set<ModuleId>> _active({
  required Set<ModuleId> stored,
  UserProfile? profile,
}) async {
  final container = _container(
    modules: InMemoryModuleStore(stored),
    profile: InMemoryUserProfileStore(profile),
  );
  await container.read(enabledModulesProvider.future);
  await container.read(userProfileProvider.future);
  final value = container.read(activeModulesProvider);
  return value;
}

void main() {
  group('energyUnderageProvider', () {
    test('is null while the profile loads', () async {
      final profile = _PendingProfileStore();
      final container = _container(
        modules: InMemoryModuleStore(),
        profile: profile,
      );

      expect(container.read(energyUnderageProvider), isNull);

      profile.release.complete(_aged(energyAdultAge - 1));
      await container.read(userProfileProvider.future);

      expect(container.read(energyUnderageProvider), isTrue);
    });

    test('is false with no profile', () async {
      expect(await _underage(), isFalse);
    });

    test('is false with a profile that has no birth year', () async {
      expect(
        await _underage(profile: const UserProfile(sex: Sex.female)),
        isFalse,
      );
    });

    test('is false at the adult age', () async {
      expect(await _underage(profile: _aged(energyAdultAge)), isFalse);
    });

    test('is true one year below the adult age', () async {
      expect(await _underage(profile: _aged(energyAdultAge - 1)), isTrue);
    });

    test('is false well above the adult age', () async {
      expect(await _underage(profile: _aged(energyAdultAge + 40)), isFalse);
    });

    test('is true on the last day of December before the 18th year', () async {
      const born = 2000;

      expect(
        await _underage(
          profile: const UserProfile(birthYear: born),
          now: DateTime.utc(born + energyAdultAge - 1, 12, 31, 23),
        ),
        isTrue,
      );
    });

    test('is false on the first day of January of the 18th year', () async {
      const born = 2000;

      expect(
        await _underage(
          profile: const UserProfile(birthYear: born),
          now: DateTime.utc(born + energyAdultAge, 1, 1, 1),
        ),
        isFalse,
      );
    });
  });

  group('activeModulesProvider', () {
    test('drops Energy at 17 and keeps the other modules', () async {
      expect(
        await _active(
          stored: const {ModuleId.body, ModuleId.energy},
          profile: _aged(energyAdultAge - 1),
        ),
        {ModuleId.body},
      );
    });

    test('keeps both at 30', () async {
      expect(
        await _active(
          stored: const {ModuleId.body, ModuleId.energy},
          profile: _aged(30),
        ),
        {ModuleId.body, ModuleId.energy},
      );
    });

    test('keeps Energy at exactly the adult age', () async {
      expect(
        await _active(
          stored: const {ModuleId.energy},
          profile: _aged(energyAdultAge),
        ),
        {ModuleId.energy},
      );
    });

    test('keeps Energy with no profile', () async {
      expect(await _active(stored: const {ModuleId.body, ModuleId.energy}), {
        ModuleId.body,
        ModuleId.energy,
      });
    });

    test('keeps Energy with no birth year', () async {
      expect(
        await _active(
          stored: const {ModuleId.energy},
          profile: const UserProfile(sex: Sex.female),
        ),
        {ModuleId.energy},
      );
    });

    test('drops Energy while the profile loads', () async {
      final profile = _PendingProfileStore();
      final container = _container(
        modules: InMemoryModuleStore(const {ModuleId.body, ModuleId.energy}),
        profile: profile,
      );
      await container.read(enabledModulesProvider.future);

      expect(container.read(activeModulesProvider), {ModuleId.body});

      profile.release.complete(_aged(30));
      await container.read(userProfileProvider.future);

      expect(container.read(activeModulesProvider), {
        ModuleId.body,
        ModuleId.energy,
      });
    });

    test('is empty while the modules load', () async {
      final modules = _PendingModuleStore();
      final container = _container(
        modules: modules,
        profile: InMemoryUserProfileStore(_aged(30)),
      );
      await container.read(userProfileProvider.future);

      expect(container.read(activeModulesProvider), isEmpty);

      modules.release.complete(const {ModuleId.energy});
      await container.read(enabledModulesProvider.future);

      expect(container.read(activeModulesProvider), {ModuleId.energy});
    });

    test('does not erase the stored value of an under 18', () async {
      final store = InMemoryModuleStore(const {ModuleId.energy});
      final container = _container(
        modules: store,
        profile: InMemoryUserProfileStore(_aged(energyAdultAge - 1)),
      );
      await container.read(enabledModulesProvider.future);
      await container.read(userProfileProvider.future);

      expect(container.read(activeModulesProvider), isEmpty);
      expect(await store.read(), {ModuleId.energy});
      expect(container.read(enabledModulesProvider).value, {ModuleId.energy});
    });
  });
}
