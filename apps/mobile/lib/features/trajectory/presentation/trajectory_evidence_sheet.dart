import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';

enum TrajectoryEvidence { rate, firm, band }

// An edge raised by less than this is a rounding difference, not the floor.
const _floorTolerance = 0.05;

GoalEvidenceCopy trajectoryEvidenceCopy(
  UnitFormat units,
  TrajectoryEvidence kind,
) {
  final format = units.format;
  final l10n = units.l10n;
  return switch (kind) {
    TrajectoryEvidence.rate => (
      title: l10n.bodyWeightRate,
      what: l10n.trajectorySheetRateWhat(format.integer(weightRateWindowDays)),
      rule: l10n.trajectorySheetRateRule(
        format.integer(weightRateMinDays),
        format.integer(weightRateMinSpanDays),
      ),
      source: l10n.trajectorySheetRateSource,
      ours: l10n.trajectorySheetRateOurs(
        format.integer(weightRateWindowDays),
        format.integer(weightRateMinDays),
        format.integer(weightRateMinSpanDays),
      ),
      limits: l10n.trajectorySheetRateLimits,
    ),
    TrajectoryEvidence.firm => (
      title: l10n.trajectorySheetFirmTitle(
        format.integer(trajectoryFirmDays ~/ 7),
      ),
      what: l10n.trajectorySheetFirmWhat,
      rule: _scenarioRule(units),
      source: l10n.trajectorySheetScenarioSource,
      ours: l10n.trajectorySheetFirmOurs,
      limits: l10n.trajectorySheetFirmLimits,
    ),
    TrajectoryEvidence.band => (
      title: l10n.trajectorySheetBandTitle(
        format.integer(trajectoryBandDays ~/ 7),
      ),
      what: l10n.trajectorySheetBandWhat,
      rule: _scenarioRule(units),
      source: l10n.trajectorySheetScenarioSource,
      ours: l10n.trajectorySheetBandOurs(
        format.decimal(trajectoryFastLossPercent),
      ),
      limits: l10n.trajectorySheetBandLimits,
    ),
  };
}

String _scenarioRule(UnitFormat units) =>
    units.l10n.trajectorySheetScenarioRule(
      units.format.integer(trajectoryAdaptationDays),
    );

/// The reader's own numbers for the sheet of [kind], with the math filled in.
String trajectoryEvidenceYours(
  UnitFormat units,
  TrajectoryEvidence kind,
  TrajectoryReady view,
) => switch (kind) {
  TrajectoryEvidence.rate => _rateYours(units, view.rate),
  TrajectoryEvidence.firm => _scenarioYours(units, view, view.firm),
  TrajectoryEvidence.band => _scenarioYours(units, view, view.band),
};

String _perWeek(UnitFormat units, double kilograms) =>
    units.format.signed(units.bodyWeightIn(kilograms), digits: 2);

String _rateYours(UnitFormat units, WeightRateReady rate) {
  final l10n = units.l10n;
  final value = _perWeek(units, rate.perWeek);
  final low = _perWeek(units, rate.low);
  final high = _perWeek(units, rate.high);
  if (rate.stable) {
    return l10n.trajectorySheetRateYoursStable(
      value,
      low,
      high,
      units.weightUnit,
    );
  }
  return l10n.trajectorySheetRateYours(value, low, high, units.weightUnit);
}

String _scenarioYours(
  UnitFormat units,
  TrajectoryReady view,
  ScenarioBand band,
) {
  final l10n = units.l10n;
  final format = units.format;
  final text = l10n.trajectorySheetScenarioYours(
    units.bodyWeight(view.trendKg),
    _perWeek(units, view.rate.low),
    _perWeek(units, view.rate.high),
    units.weightUnit,
    format.integer(band.days),
    format.decimal(scenarioDays(band.days), digits: 1),
    units.bodyWeight(band.mid),
    units.bodyWeight(view.noiseKg),
    l10n.trajectoryRange(
      units.bodyWeightNumber(band.low),
      units.bodyWeightNumber(band.high),
      units.weightUnit,
    ),
  );
  final raw = weightScenario(view.trendKg, view.rate, view.noiseKg, band.days);
  if (band.low <= raw.low + _floorTolerance) return text;
  final floor = l10n.trajectorySheetScenarioFloor(
    format.decimal(bmiFloor, digits: 1),
  );
  return '$text $floor';
}
