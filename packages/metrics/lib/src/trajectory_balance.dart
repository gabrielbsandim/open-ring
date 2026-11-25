import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/energy.dart';
import 'package:metrics/src/food_energy.dart';
import 'package:metrics/src/local_date.dart';
import 'package:metrics/src/weight_trend.dart';

// The first day whose 28 day window holds none of the first 14 days of a goal
// block, when water and glycogen move faster than tissue.
const int trajectoryBalanceHoldDays =
    weightRateWindowDays + foodEnergyGoalHoldDays - 1;

sealed class EnergyBalance {
  const new();
}

final class EnergyBalanceNoRate extends EnergyBalance {
  const new();
}

final class EnergyBalanceCount extends EnergyBalance {
  const new(this.weighIns);

  final int weighIns;
}

final class EnergyBalanceBlock extends EnergyBalance {
  const new(this.from);

  final LocalDate from;
}

final class EnergyBalanceReady extends EnergyBalance {
  const new({
    required this.low,
    required this.mid,
    required this.high,
    required this.weighIns,
  });

  final double low;
  final double mid;
  final double high;
  final int weighIns;

  EnergyRange get shown => (low: energyStepped(low), high: energyStepped(high));

  bool get balanced => low <= 0 && high >= 0;
}

/// The kcal a day the weight change of the 28 day window stands for, below
/// zero when less was eaten than spent.
EnergyBalance energyBalance({
  required Iterable<DailyValue> weighIns,
  required WeightRate rate,
  required LocalDate today,
  LocalDate? goalBlockStart,
}) {
  if (rate is! WeightRateReady) return const EnergyBalanceNoRate();
  final count = dailyWeights(weighIns).where((day) {
    final age = today.daysSince(day.date);
    return age >= 0 && age < weightRateWindowDays;
  }).length;
  if (count < foodEnergyMinWeighIns) return EnergyBalanceCount(count);
  final held = goalBlockStart == null ? null : today.daysSince(goalBlockStart);
  if (held != null && held >= 0 && held < trajectoryBalanceHoldDays) {
    return EnergyBalanceBlock(
      goalBlockStart!.addDays(trajectoryBalanceHoldDays),
    );
  }
  double kcal(double perWeek) => perWeek / 7 * foodEnergyKcalPerKg;
  return EnergyBalanceReady(
    low: kcal(rate.low),
    mid: kcal(rate.perWeek),
    high: kcal(rate.high),
    weighIns: count,
  );
}
