import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/energy/presentation/energy_evidence_sheet.dart';

enum EffortEvidence { points, strength, lines, walk, session, coach }

abstract final class EffortEvidenceKeys {
  static const sheet = Key('effort_evidence');
  static const title = Key('effort_evidence_title');
  static const yours = Key('effort_evidence_yours');
  static const rule = Key('effort_evidence_rule');
  static const source = Key('effort_evidence_source');
  static const ours = Key('effort_evidence_ours');
  static const limits = Key('effort_evidence_limits');
  static const formula = Key('effort_evidence_formula');
}

typedef EffortEvidenceCopy = ({
  String title,
  String what,
  String rule,
  String source,
  String ours,
  String limits,
});

String _plain(MetricFormat format, double value) =>
    format.decimal(value, digits: value == value.roundToDouble() ? 0 : 1);

double _share(int days) => 2 / (days + 1);

EffortEvidenceCopy effortEvidenceCopy(
  MetricFormat format,
  EffortEvidence kind,
) {
  final l10n = format.l10n;
  final points = format.integer(effortWeekPoints);
  final strengthDays = format.integer(effortWeekStrengthDays);
  final strengthMinutes = format.integer(effortStrengthMinMinutes);
  final acute = format.integer(effortAcuteDays);
  final chronic = format.integer(effortChronicDays);
  final cadence = format.integer(briskStepsPerMinute);
  final walking = _plain(format, effortWalkingLoadFactor);
  return switch (kind) {
    EffortEvidence.points => (
      title: l10n.effortFormulaPointsTitle,
      what: l10n.effortSheetPointsWhat(_plain(format, vigorousMinuteWeight)),
      rule: l10n.effortSheetPointsRule,
      source: l10n.effortSheetPointsSource(points),
      ours: l10n.effortSheetPointsOurs,
      limits: l10n.effortSheetPointsLimits(points),
    ),
    EffortEvidence.strength => (
      title: l10n.effortSheetStrengthTitle,
      what: l10n.effortSheetStrengthWhat,
      rule: l10n.effortSheetStrengthRule(strengthMinutes),
      source: l10n.effortSheetStrengthSource(strengthDays),
      ours: l10n.effortSheetStrengthOurs(strengthMinutes),
      limits: l10n.effortSheetStrengthLimits,
    ),
    EffortEvidence.lines => (
      title: l10n.effortSheetLinesTitle,
      what: l10n.effortSheetLinesWhat(acute, chronic),
      rule: l10n.effortSheetLinesRule(
        format.decimal(_share(effortAcuteDays), digits: 2),
        acute,
        format.decimal(_share(effortChronicDays), digits: 3),
        chronic,
        format.integer(effortLineSeedDays),
      ),
      source: l10n.effortSheetLinesSource,
      ours: l10n.effortSheetLinesOurs,
      limits: l10n.effortLoadNote,
    ),
    EffortEvidence.walk => (
      title: l10n.effortBriskWalking,
      what: l10n.effortSheetWalkWhat,
      rule: l10n.effortSheetWalkRule(cadence, walking),
      source: l10n.effortSheetWalkSource(cadence),
      ours: l10n.effortSheetWalkOurs(walking),
      limits: l10n.effortSheetWalkLimits,
    ),
    EffortEvidence.session => (
      title: l10n.effortFormulaLoadTitle,
      what: l10n.effortSheetSessionWhat,
      rule: l10n.effortSheetSessionRule,
      source: l10n.effortSheetSessionSource,
      ours: l10n.effortSheetSessionOurs,
      limits: l10n.effortFormulaCannot1,
    ),
    EffortEvidence.coach => (
      title: l10n.effortFormulaCoachTitle,
      what: l10n.effortSheetCoachWhat,
      rule: l10n.effortSheetCoachRule(format.integer(CoachRule.values.length)),
      source: l10n.effortSheetCoachSource,
      ours: l10n.effortFormulaOurs5,
      limits: l10n.effortFormulaCannot4,
    ),
  };
}

/// Opens the sheet of [kind] with the reader's own numbers in [yours].
Future<void> showEffortEvidence(
  BuildContext context, {
  required EffortEvidence kind,
  required String yours,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.of(context).surface,
  builder: (context) => SafeArea(
    child: EffortEvidenceSheet(kind: kind, yours: yours),
  ),
);

class EffortEvidenceSheet extends StatelessWidget {
  const new({required this.kind, required this.yours, super.key});

  final EffortEvidence kind;
  final String yours;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final copy = effortEvidenceCopy(format, kind);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        key: EffortEvidenceKeys.sheet,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                copy.title,
                key: EffortEvidenceKeys.title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            EnergyEvidenceSection(
              title: l10n.overallSheetWhat,
              body: copy.what,
            ),
            EnergyEvidenceSection(
              key: EffortEvidenceKeys.yours,
              title: l10n.overallSheetYours,
              body: yours,
            ),
            EnergyEvidenceSection(
              key: EffortEvidenceKeys.rule,
              title: l10n.overallSheetRule,
              body: copy.rule,
            ),
            EnergyEvidenceSection(
              key: EffortEvidenceKeys.source,
              title: l10n.overallSheetSource,
              body: copy.source,
            ),
            EnergyEvidenceSection(
              key: EffortEvidenceKeys.ours,
              title: l10n.overallSheetOurs,
              body: copy.ours,
            ),
            EnergyEvidenceSection(
              key: EffortEvidenceKeys.limits,
              title: l10n.overallSheetLimits,
              body: copy.limits,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: EffortEvidenceKeys.formula,
                onPressed: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  unawaited(router.push(AppPaths.effortFormula));
                },
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(l10n.formulaLink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
