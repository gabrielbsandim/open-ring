import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/trajectory/application/steps_what_if_providers.dart';
import 'package:open_ring/features/trajectory/application/trajectory_kcal_providers.dart';

enum KcalEvidence { resting, scenario, balance }

enum WhatIfEvidence { weight, cohort }

GoalEvidenceCopy kcalEvidenceCopy(MetricFormat format, KcalEvidence kind) {
  final l10n = format.l10n;
  return switch (kind) {
    KcalEvidence.resting => (
      title: l10n.trajectoryKcalResting,
      what: l10n.trajectorySheetRestingWhat,
      rule: l10n.trajectorySheetRestingRule,
      source: l10n.trajectorySheetRestingSource,
      ours: l10n.trajectorySheetRestingOurs,
      limits: l10n.trajectorySheetRestingLimits,
    ),
    KcalEvidence.scenario => (
      title: l10n.trajectoryKcalScenario,
      what: l10n.trajectorySheetBurnWhat,
      rule: l10n.trajectorySheetBurnRule(format.integer(10)),
      source: l10n.trajectorySheetBurnSource,
      ours: l10n.trajectorySheetBurnOurs(
        format.decimal(trajectoryKcalPerKgDay),
      ),
      limits: l10n.trajectorySheetBurnLimits,
    ),
    KcalEvidence.balance => (
      title: l10n.trajectoryKcalBalance,
      what: l10n.trajectorySheetBalanceWhat,
      rule: l10n.trajectorySheetBalanceRule(
        format.integer(foodEnergyKcalPerKg),
        format.integer(energyRangeStep),
      ),
      source: l10n.trajectorySheetBalanceSource(
        format.integer(foodEnergyKcalPerKg),
      ),
      ours: l10n.trajectorySheetBalanceOurs(
        format.integer(foodEnergyMinWeighIns),
        format.integer(weightRateWindowDays),
        format.integer(foodEnergyGoalHoldDays),
      ),
      limits: l10n.trajectorySheetBalanceLimits,
    ),
  };
}

/// The reader's own numbers for the kcal sheet of [kind]; [scenarioKg] is the
/// middle of the 12 week band minus today's trend.
String kcalEvidenceYours(
  UnitFormat units,
  KcalEvidence kind,
  KcalReady kcal, {
  required double scenarioKg,
}) {
  final format = units.format;
  final l10n = units.l10n;
  return switch (kind) {
    KcalEvidence.resting => l10n.trajectorySheetRestingYours(
      _range(format, kcal.resting),
      format.integer(energyRestingMargin * 100),
    ),
    KcalEvidence.scenario => _burnYours(units, kcal, scenarioKg),
    KcalEvidence.balance => _balanceYours(format, kcal.balance),
  };
}

String _range(MetricFormat format, EnergyRange? range) {
  if (range == null) return '';
  return format.l10n.trajectoryKcalRange(
    format.integer(range.low),
    format.integer(range.high),
  );
}

String _burnYours(UnitFormat units, KcalReady kcal, double scenarioKg) {
  final l10n = units.l10n;
  final format = units.format;
  final rest = kcal.restChange12;
  final day = kcal.dayChange12;
  if (rest == null || day == null || rest == 0) {
    return l10n.trajectoryKcalSameWhy;
  }
  final amount = units.bodyWeight(scenarioKg.abs());
  final kilograms = format.decimal(scenarioKg.abs(), digits: 2);
  final perKg = format.decimal(mifflinPerKilogram, digits: 2);
  final wholePerKg = format.decimal(trajectoryKcalPerKgDay);
  if (scenarioKg < 0) {
    return l10n.trajectorySheetBurnLess(
      amount,
      perKg,
      kilograms,
      format.integer(rest.abs()),
      wholePerKg,
      format.integer(day.abs()),
    );
  }
  return l10n.trajectorySheetBurnMore(
    amount,
    perKg,
    kilograms,
    format.integer(rest.abs()),
    wholePerKg,
    format.integer(day.abs()),
  );
}

String _balanceYours(MetricFormat format, EnergyBalance balance) {
  final l10n = format.l10n;
  return switch (balance) {
    EnergyBalanceNoRate() => l10n.trajectoryKcalNoRateWhy,
    EnergyBalanceCount(:final weighIns) => l10n.trajectoryKcalCountWhy(
      format.integer(foodEnergyMinWeighIns),
      format.integer(weighIns),
    ),
    EnergyBalanceBlock(:final from) =>
      '${l10n.trajectoryKcalBlockWhy} '
          '${l10n.trajectoryKcalFromDate(format.monthDay(from))}',
    EnergyBalanceReady(:final low, :final mid, :final high, :final weighIns) =>
      l10n.trajectorySheetBalanceYours(
        format.integer(mid.round()),
        format.integer(low.round()),
        format.integer(high.round()),
        format.integer(weighIns),
        format.integer(foodEnergyKcalPerKg),
      ),
  };
}

GoalEvidenceCopy whatIfEvidenceCopy(MetricFormat format, WhatIfEvidence kind) {
  final l10n = format.l10n;
  return switch (kind) {
    WhatIfEvidence.weight => (
      title: l10n.trajectoryWhatIfWeightTitle,
      what: l10n.trajectorySheetStepsWhat,
      rule: l10n.trajectorySheetStepsRule,
      source: l10n.trajectorySheetStepsSource,
      ours: l10n.trajectorySheetStepsOurs,
      limits: l10n.trajectorySheetStepsLimits,
    ),
    WhatIfEvidence.cohort => (
      title: l10n.trajectoryWhatIfStudiesTitle,
      what: l10n.trajectorySheetCohortWhat,
      rule: l10n.trajectorySheetCohortRule,
      source: l10n.trajectorySheetCohortSource,
      ours: l10n.trajectorySheetCohortOurs,
      limits: l10n.trajectorySheetCohortLimits,
    ),
  };
}

/// The weight sheet's numbers; kcal only when [energy] is on.
String whatIfWeightYours(
  UnitFormat units,
  StepsWhatIf weight, {
  required bool hidden,
  required bool energy,
}) {
  final l10n = units.l10n;
  final format = units.format;
  final distance = units.distanceText(weight.kilometers * metersPerKilometre);
  if (hidden) return l10n.trajectoryWhatIfHiddenWhy(distance);
  String amount(double kilograms) =>
      '${format.decimal(units.bodyWeightIn(kilograms), digits: 2)} '
      '${units.weightUnit}';
  final total = amount(weight.kcalPerDay / trajectoryKcalPerKgDay);
  final four = amount(weight.kgLess4);
  final twelve = amount(weight.kgLess12);
  if (!energy) {
    return l10n.trajectorySheetStepsYours(distance, total, four, twelve);
  }
  return l10n.trajectorySheetStepsYoursKcal(
    distance,
    format.integer(weight.kcalPerDay.round()),
    total,
    four,
    twelve,
  );
}

String whatIfCohortYours(MetricFormat format, WhatIfReady ready, String words) {
  final from = paluchHazard(ready.typical);
  final to = paluchHazard(ready.toSteps);
  final ratio = to / from;
  final text = format.l10n.trajectorySheetCohortYours(
    format.integer(ready.typical),
    format.integer(ready.toSteps),
    format.decimal(from, digits: 2),
    format.decimal(to, digits: 2),
    format.decimal(ratio, digits: 2),
    format.decimal((1 - ratio) * 100, digits: 1),
    words,
  );
  if (!ready.clamped) return text;
  final clamped = format.l10n.trajectoryWhatIfClamped(
    format.integer(paluchAnchors.last.steps),
  );
  return '$text $clamped';
}
