import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/energy/presentation/energy_parts.dart';

enum EnergyEvidence { resting, base, steps, workouts }

abstract final class EnergyEvidenceKeys {
  static const sheet = Key('energy_evidence');
  static const title = Key('energy_evidence_title');
  static const yours = Key('energy_evidence_yours');
  static const rule = Key('energy_evidence_rule');
  static const ours = Key('energy_evidence_ours');
  static const note = Key('energy_evidence_note');
}

EnergyEvidence energyEvidenceOf(EnergyPart part) => switch (part) {
  EnergyPart.base => EnergyEvidence.base,
  EnergyPart.steps => EnergyEvidence.steps,
  EnergyPart.workouts => EnergyEvidence.workouts,
};

typedef _Copy = ({
  String title,
  String what,
  String yours,
  String rule,
  String source,
  String ours,
  String limits,
});

String _percent(MetricFormat format, double share) =>
    format.integer(share * 100);

String _restingText(MetricFormat format, double resting) {
  final range = energyRange(resting, energyRestingMargin);
  final text = format.l10n.energyRowRange(
    format.integer(range.low),
    format.integer(range.high),
  );
  return '$text ${format.l10n.energyRestingUnit}';
}

String _workoutsText(MetricFormat format, double value) => value <= 0
    ? format.l10n.energyPartWorkoutsNone
    : energyPartText(format, value);

_Copy _copy(MetricFormat format, EnergyEvidence kind, EnergyDayEstimate day) {
  final l10n = format.l10n;
  String two(double value) => format.decimal(value, digits: 2);
  final factor = format.decimal(energyBaseFactor, digits: 1);
  final cost = format.decimal(energyWalkCostPerKgKm, digits: 1);
  final margin = _percent(format, energyRestingMargin);
  return switch (kind) {
    EnergyEvidence.resting => (
      title: l10n.energyRestingTitle,
      what: l10n.energyWhatResting,
      yours: _restingText(format, day.resting),
      rule: l10n.energyRuleResting(
        two(mifflinPerKilogram),
        two(mifflinPerCentimeter),
        two(mifflinPerYear),
        format.integer(mifflinMaleOffset),
        format.integer(mifflinFemaleOffset.abs()),
        margin,
        format.integer(energyRangeStep),
      ),
      source: l10n.energySourceResting,
      ours: l10n.energyOursResting(margin),
      limits: l10n.energyLimitsResting(format.integer(energyAdultAge)),
    ),
    EnergyEvidence.base => (
      title: l10n.energyPartBase,
      what: l10n.energyWhatBase,
      yours: energyPartText(format, day.base),
      rule: l10n.energyRuleBase(factor),
      source: l10n.energySourceBase,
      ours: l10n.energyOursBase(factor),
      limits: l10n.energyLimitsBase,
    ),
    EnergyEvidence.steps => (
      title: l10n.energyPartSteps,
      what: l10n.energyWhatSteps,
      yours: energyPartText(format, day.steps),
      rule: l10n.energyRuleSteps(
        format.decimal(energyStepLengthFactor, digits: 3),
        cost,
      ),
      source: l10n.energySourceSteps,
      ours: l10n.energyOursSteps(cost),
      limits: l10n.energyLimitsSteps,
    ),
    EnergyEvidence.workouts => (
      title: l10n.energyPartWorkouts,
      what: l10n.energyWhatWorkouts,
      yours: _workoutsText(format, day.workouts),
      rule: l10n.energyRuleWorkouts,
      source: l10n.energySourceWorkouts,
      ours: l10n.energyOursWorkouts,
      limits: l10n.energyLimitsWorkouts,
    ),
  };
}

Future<void> showEnergyEvidence(
  BuildContext context, {
  required EnergyEvidence kind,
  required EnergyDayEstimate day,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.of(context).surface,
  builder: (context) => SafeArea(
    child: EnergyEvidenceSheet(kind: kind, day: day),
  ),
);

class EnergyEvidenceSheet extends StatelessWidget {
  const new({required this.kind, required this.day, super.key});

  final EnergyEvidence kind;
  final EnergyDayEstimate day;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final copy = _copy(format, kind, day);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        key: EnergyEvidenceKeys.sheet,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                copy.title,
                key: EnergyEvidenceKeys.title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            _Section(title: l10n.overallSheetWhat, body: copy.what),
            _Section(
              key: EnergyEvidenceKeys.yours,
              title: l10n.overallSheetYours,
              body: copy.yours,
            ),
            _Section(
              key: EnergyEvidenceKeys.rule,
              title: l10n.overallSheetRule,
              body: copy.rule,
            ),
            _Section(title: l10n.overallSheetSource, body: copy.source),
            _Section(
              key: EnergyEvidenceKeys.ours,
              title: l10n.overallSheetOurs,
              body: copy.ours,
            ),
            _Section(title: l10n.overallSheetLimits, body: copy.limits),
            const SizedBox(height: 16),
            CaptionText(l10n.energyFixedNote, key: EnergyEvidenceKeys.note),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const new({required this.title, required this.body, super.key});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: AppColors.of(context).textLabel),
        ),
        const SizedBox(height: 4),
        BodyText(body),
      ],
    ),
  );
}
