import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart' show LocalDate;
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/domain/food_energy_store.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';

final foodEnergyStoreProvider = Provider<FoodEnergyStore>(
  (ref) => InMemoryFoodEnergyStore(),
);

/// Why Weekly energy is not offered, in the order the checks run.
enum FoodEnergyBlock {
  bodyOff,
  softMode,
  ageMissing,
  under18,
  heightMissing,
  bmiUnderFloor,
  pregnancy,
  sexMissing,
}

sealed class FoodEnergyGate {
  const new();
}

/// AI or Food is off.
final class FoodEnergyHidden extends FoodEnergyGate {
  const new();
}

final class FoodEnergyDemo extends FoodEnergyGate {
  const new();
}

final class FoodEnergyBlocked extends FoodEnergyGate {
  const new(this.block);

  final FoodEnergyBlock block;
}

final class FoodEnergyNeedsScreening extends FoodEnergyGate {
  const new();
}

final class FoodEnergyOn extends FoodEnergyGate {
  const new(this.since);

  final LocalDate since;
}

final class FoodEnergyOffered extends FoodEnergyGate {
  const new(this.screenedOn);

  final LocalDate screenedOn;
}

/// The first state that applies wins.
final foodEnergyGateProvider = FutureProvider<FoodEnergyGate>((ref) async {
  if (!ref.watch(aiEnabledProvider) || !ref.watch(foodEnabledProvider)) {
    return const FoodEnergyHidden();
  }
  if (ref.watch(demoModeProvider)) return const FoodEnergyDemo();
  ref.watch(dataRevisionProvider);
  final facts = await ref.watch(intakeFactsProvider.future);
  final pregnancy = await ref.watch(newestPregnancyProvider.future);
  final profile = await ref.watch(userProfileProvider.future);
  final block = switch (weightGoalBlock(facts)) {
    final IntakeBlock intake => FoodEnergyBlock.values.byName(intake.name),
    null when pregnancy == true => FoodEnergyBlock.pregnancy,
    null when profile?.sex == null => FoodEnergyBlock.sexMissing,
    null => null,
  };
  if (block != null) return FoodEnergyBlocked(block);
  if (facts.softMode == null) return const FoodEnergyNeedsScreening();
  final screenings = await ref.watch(goalStoreProvider).screenings();
  final optIn = await ref.watch(foodEnergyStoreProvider).read();
  if (optIn != null && optIn.softSeen == _softCount(screenings)) {
    return FoodEnergyOn(optIn.on);
  }
  return FoodEnergyOffered(screenings.firstWhere((s) => s.softMode != null).on);
});

int _softCount(List<GoalScreening> screenings) =>
    screenings.where((s) => s.softMode == true).length;

final foodEnergyOptInControllerProvider =
    AsyncNotifierProvider<FoodEnergyOptInController, void>(
      FoodEnergyOptInController.new,
    );

class FoodEnergyOptInController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Stores today and the soft mode count. False, writing nothing, in demo
  /// mode or unless the gate offers it.
  Future<bool> turnOn() async {
    if (ref.read(demoModeProvider)) return false;
    final gate = await ref.read(foodEnergyGateProvider.future);
    if (gate is! FoodEnergyOffered) return false;
    final screenings = await ref.read(goalStoreProvider).screenings();
    await ref.read(foodEnergyStoreProvider).write((
      on: ref.read(currentDateProvider),
      softSeen: _softCount(screenings),
    ));
    if (ref.mounted) ref.invalidate(foodEnergyGateProvider);
    return true;
  }

  /// Removes the opt in; stored items stay.
  Future<void> turnOff() async {
    await ref.read(foodEnergyStoreProvider).clear();
    if (ref.mounted) ref.invalidate(foodEnergyGateProvider);
  }
}
