import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/domain/review_inputs.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/trajectory/domain/in_memory_projection_store.dart';
import 'package:open_ring/features/trajectory/domain/monday_projection.dart';
import 'package:open_ring/features/trajectory/domain/projection_store.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';

final projectionStoreProvider = Provider<ProjectionStore>(
  (ref) => InMemoryProjectionStore(),
);

final trajectoryViewProvider = FutureProvider<TrajectoryView>((ref) async {
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  try {
    final modules = await ref.watch(enabledModulesProvider.future);
    if (!modules.contains(ModuleId.trajectory)) return const TrajectoryOff();
    if (!modules.contains(ModuleId.body)) return const TrajectoryOff();
    final refusal = await _refusal(ref, today);
    if (refusal != null) return TrajectoryRefused(refusal);
    final profile = await ref.watch(userProfileProvider.future);
    final summary = await ref.watch(weightSummaryProvider.future);
    final view = _view(today, summary, profile!.heightCentimeters!);
    if (view is! TrajectoryReady || ref.watch(demoModeProvider)) return view;
    // Leaving demo flips the flag before the cached weigh-ins are refreshed.
    final entries = await ref.watch(weighInsProvider.future);
    if (entries.any((entry) => entry.source == WeighInSource.demo)) return view;
    await _storeMonday(ref, today, summary!.daily);
    return view;
  } on Object catch (error) {
    return TrajectoryError(error);
  }
});

Future<TrajectoryRefusal?> _refusal(Ref ref, LocalDate today) async {
  final profile = await ref.watch(userProfileProvider.future);
  final age = profile?.ageIn(today.year);
  if (age != null && age < energyAdultAge) return TrajectoryRefusal.underage;
  if (await ref.watch(newestPregnancyProvider.future) ?? false) {
    return TrajectoryRefusal.pregnancy;
  }
  // Height is required up front for the BMI floor the drawn band applies.
  if (profile?.heightCentimeters == null) return TrajectoryRefusal.noHeight;
  return null;
}

TrajectoryView _view(LocalDate today, WeightSummary? summary, double heightCm) {
  if (summary == null) return const TrajectoryBuilding(null);
  final snapshot = weightSnapshot(daily: summary.daily, asOf: today);
  final rate = snapshot.rate;
  final trendKg = snapshot.trendKg;
  if (rate is WeightRateBuilding) return TrajectoryBuilding(rate);
  if (rate is! WeightRateReady || trendKg == null) {
    return const TrajectoryBuilding(null);
  }
  final loss = lossRate(rate, trendKg);
  if (fastLossGuard(loss)) return TrajectoryGuard(loss);
  return TrajectoryReady(
    asOf: today,
    trendKg: trendKg,
    rate: rate,
    noiseKg: summary.noise,
    firm: scenarioFloored(
      weightScenario(trendKg, rate, summary.noise, trajectoryFirmDays),
      trendKg: trendKg,
      heightCm: heightCm,
    ),
    band: scenarioFloored(
      weightScenario(trendKg, rate, summary.noise, trajectoryBandDays),
      trendKg: trendKg,
      heightCm: heightCm,
    ),
  );
}

// A failed write keeps the card: the band is shown again on the next open.
Future<void> _storeMonday(
  Ref ref,
  LocalDate today,
  List<DailyValue> daily,
) async {
  final projection = mondayProjection(
    today: today,
    daily: daily,
    createdAt: ref.read(clockProvider)(),
  );
  if (projection == null) return;
  try {
    await ref.read(projectionStoreProvider).insertIfAbsent(projection);
  } on Object catch (error) {
    debugPrint('Trajectory projection was not stored: $error');
  }
}
