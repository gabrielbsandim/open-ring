import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/energy/presentation/energy_evidence_sheet.dart';
import 'package:open_ring/features/goals/domain/goal_path.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';

enum GoalEvidence { rate, trend, arrival }

abstract final class GoalEvidenceKeys {
  static const sheet = Key('goal_evidence');
  static const title = Key('goal_evidence_title');
  static const yours = Key('goal_evidence_yours');
  static const rule = Key('goal_evidence_rule');
  static const ours = Key('goal_evidence_ours');
}

typedef GoalEvidenceCopy = ({
  String title,
  String what,
  String rule,
  String source,
  String ours,
  String limits,
});

/// A percent with one decimal when that is exact, two otherwise.
String goalPercent(MetricFormat format, double value) => format.decimal(
  value,
  digits: (value * 10).roundToDouble() == value * 10 ? 1 : 2,
);

String goalRateAmount(UnitFormat units, double kg) =>
    '${units.format.decimal(units.bodyWeightIn(kg), digits: 2)} '
    '${units.weightUnit}';

GoalEvidenceCopy goalEvidenceCopy(MetricFormat format, GoalEvidence kind) {
  final l10n = format.l10n;
  return switch (kind) {
    GoalEvidence.rate => (
      title: l10n.goalsPathRate,
      what: l10n.goalsSheetRateWhat,
      rule: l10n.goalsSheetRateRule(
        format.integer(weightRateWindowDays),
        format.integer(weightRateMinDays),
        format.integer(weightRateMinSpanDays),
      ),
      source: l10n.goalsSheetRateSource,
      ours: l10n.goalsSheetRateOurs,
      limits: l10n.goalsSheetRateLimits,
    ),
    GoalEvidence.trend => (
      title: l10n.goalsSheetTrendTitle,
      what: l10n.goalsSheetTrendWhat,
      rule: l10n.goalsSheetTrendRule(format.integer(weightTrendAlpha * 100)),
      source: l10n.goalsSheetTrendSource,
      ours: l10n.goalsSheetTrendOurs,
      limits: l10n.goalsSheetTrendLimits,
    ),
    GoalEvidence.arrival => (
      title: l10n.goalsPathArrival,
      what: l10n.goalsSheetArrivalWhat,
      rule: l10n.goalsSheetArrivalRule(format.integer(goalMaintenanceWeeks)),
      source: l10n.goalsSheetArrivalSource,
      ours: l10n.goalsSheetArrivalOurs,
      limits: l10n.goalsSheetArrivalLimits,
    ),
  };
}

/// The reader's own numbers for the sheet of [kind].
String goalEvidenceYours(
  UnitFormat units,
  GoalEvidence kind,
  GoalPath path, {
  required bool paused,
}) {
  final format = units.format;
  final l10n = units.l10n;
  final rate = path.rate;
  final trend = path.trendKg;
  return switch (kind) {
    GoalEvidence.rate when rate != null && trend != null =>
      l10n.goalsSheetRateYours(
        goalRateAmount(units, rate.kg),
        goalRateAmount(units, rate.kgLow),
        goalRateAmount(units, rate.kgHigh),
        units.bodyWeight(trend),
        goalPercent(format, rate.percent),
        goalPercent(format, rate.percentLow),
        goalPercent(format, rate.percentHigh),
        goalPercent(format, path.targetPercent),
      ),
    GoalEvidence.rate => l10n.goalsSheetRateNone,
    GoalEvidence.trend => _trendYours(units, path),
    GoalEvidence.arrival => _arrivalYours(units, path, paused: paused),
  };
}

String _trendYours(UnitFormat units, GoalPath path) {
  final l10n = units.l10n;
  final start = path.startKg;
  final trend = path.trendKg;
  if (trend == null) return l10n.goalsSheetTrendNone;
  final now = l10n.goalsSheetTrendNow(
    units.format.date(path.on),
    units.bodyWeight(trend),
  );
  if (start == null) return now;
  return '$now ${l10n.goalsSheetTrendFrom(units.bodyWeight(start), units.bodyWeight(start - trend))}';
}

String _arrivalYours(UnitFormat units, GoalPath path, {required bool paused}) {
  final l10n = units.l10n;
  final format = units.format;
  final reference = path.referenceKg;
  final trend = path.trendKg;
  final rate = path.rate;
  final arrival = path.arrival;
  if (reference == null) return l10n.goalsSheetArrivalNoReference;
  if (paused) return l10n.goalsPathArrivalPausedDetail;
  if (trend != null && trend <= reference) {
    return l10n.goalsPathArrivalReachedDetail;
  }
  if (arrival == null || rate == null || trend == null) {
    return l10n.goalsPathArrivalNoneDetail;
  }
  return l10n.goalsSheetArrivalYours(
    units.bodyWeight(trend - reference),
    goalRateAmount(units, rate.kgHigh),
    format.decimal(arrival.earliestWeeks, digits: 1),
    goalRateAmount(units, rate.kgLow),
    format.decimal(arrival.latestWeeks, digits: 1),
    goalArrivalText(format, arrival),
  );
}

/// The months of an arrival, the year once when both ends share it.
String goalArrivalText(MetricFormat format, ArrivalRange arrival) {
  final earliest = arrival.earliest;
  final latest = arrival.latest;
  if (earliest.year == latest.year && earliest.month == latest.month) {
    return format.monthYear(latest);
  }
  final from = earliest.year == latest.year
      ? format.month(earliest)
      : format.monthYear(earliest);
  return format.l10n.goalsPathArrivalRange(from, format.monthYear(latest));
}

/// Opens a sheet of [copy] with the reader's own numbers in [yours].
Future<void> showGoalEvidence(
  BuildContext context, {
  required GoalEvidenceCopy copy,
  required String yours,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.of(context).surface,
  builder: (context) => SafeArea(
    child: GoalEvidenceSheet(copy: copy, yours: yours),
  ),
);

class GoalEvidenceSheet extends StatelessWidget {
  const new({required this.copy, required this.yours, super.key});

  final GoalEvidenceCopy copy;
  final String yours;

  @override
  Widget build(BuildContext context) {
    final l10n = MetricFormat.of(context).l10n;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        key: GoalEvidenceKeys.sheet,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                copy.title,
                key: GoalEvidenceKeys.title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            EnergyEvidenceSection(
              title: l10n.overallSheetWhat,
              body: copy.what,
            ),
            EnergyEvidenceSection(
              key: GoalEvidenceKeys.yours,
              title: l10n.overallSheetYours,
              body: yours,
            ),
            EnergyEvidenceSection(
              key: GoalEvidenceKeys.rule,
              title: l10n.overallSheetRule,
              body: copy.rule,
            ),
            EnergyEvidenceSection(
              title: l10n.overallSheetSource,
              body: copy.source,
            ),
            EnergyEvidenceSection(
              key: GoalEvidenceKeys.ours,
              title: l10n.overallSheetOurs,
              body: copy.ours,
            ),
            EnergyEvidenceSection(
              title: l10n.overallSheetLimits,
              body: copy.limits,
            ),
          ],
        ),
      ),
    );
  }
}
