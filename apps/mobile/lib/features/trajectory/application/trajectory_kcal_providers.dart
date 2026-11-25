import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/food/application/food_energy.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';

const _kcalChangeStep = 10;

sealed class TrajectoryKcal {
  const new();
}

final class KcalOff extends TrajectoryKcal {
  const new();
}

final class KcalReady extends TrajectoryKcal {
  const new({
    required this.resting,
    required this.restChange12,
    required this.dayChange12,
    required this.balance,
  });

  final EnergyRange? resting;
  final int? restChange12;
  final int? dayChange12;
  final EnergyBalance balance;
}

int _stepped(double kcal) => (kcal / _kcalChangeStep).round() * _kcalChangeStep;

final trajectoryKcalProvider = FutureProvider<TrajectoryKcal>((ref) async {
  if (ref.watch(energyGateProvider) != EnergyGate.on) return const KcalOff();
  final view = await ref.watch(trajectoryViewProvider.future);
  if (view is! TrajectoryReady) return const KcalOff();
  final day = await ref.watch(energyTodayProvider.future);
  final summary = await ref.watch(weightSummaryProvider.future);
  final goal = await ref.watch(activeGoalProvider.future);
  final kilograms = view.band.mid - view.trendKg;
  return KcalReady(
    resting: switch (day) {
      EnergyDayEstimate(:final resting) => energyRange(
        resting,
        energyRestingMargin,
      ),
      _ => null,
    },
    restChange12: _stepped(kilograms * mifflinPerKilogram),
    dayChange12: _stepped(kilograms * trajectoryKcalPerKgDay),
    balance: energyBalance(
      weighIns: summary?.daily ?? const [],
      rate: view.rate,
      today: view.asOf,
      goalBlockStart: energyBlockStart(goal),
    ),
  );
});
