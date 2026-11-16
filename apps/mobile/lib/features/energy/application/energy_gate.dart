import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';

// Under this many kcal the low end rounds to nothing readable, so the row
// says the day is starting instead of showing a range.
const energyRowFloor = 100;

enum EnergyGate { off, underage, hidden, on }

final energyGateProvider = Provider<EnergyGate>((ref) {
  final modules = ref.watch(enabledModulesProvider).value;
  if (modules == null || !modules.contains(ModuleId.energy)) {
    return EnergyGate.off;
  }
  final profile = ref.watch(userProfileProvider);
  if (!profile.hasValue) return EnergyGate.off;
  // The year of the instant the day is computed at, so the gate and the day
  // agree on the age after a resume in a new year.
  final asOf = ref.watch(energyAsOfProvider);
  final year = LocalDate.fromInstant(asOf, asOf.timeZoneOffset).year;
  final age = profile.value?.ageIn(year);
  if (age != null && age < energyAdultAge) return EnergyGate.underage;
  if (ref.watch(profileWeightHiddenProvider)) return EnergyGate.hidden;
  return EnergyGate.on;
});
