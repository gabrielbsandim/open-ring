import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class OverallEvidenceKeys {
  static const sheet = Key('overall_evidence');
  static const title = Key('overall_evidence_title');
  static const points = Key('overall_evidence_points');
  static const yours = Key('overall_evidence_yours');
  static const window = Key('overall_evidence_window');
  static const rule = Key('overall_evidence_rule');
  static const parts = Key('overall_evidence_parts');
  static const association = Key('overall_evidence_association');
}

// Body points give the measure back, so they hide with the numbers.
bool overallSecret(OverallFactor factor, {required bool hidden}) =>
    hidden && factor == OverallFactor.body;

String overallValueText(
  MetricFormat format,
  OverallFactor factor,
  OverallInputs inputs, {
  required bool hidden,
}) {
  final l10n = format.l10n;
  return switch (factor) {
    OverallFactor.fitness => l10n.overallValueFitness(
      format.integer(inputs.fitnessPercentile ?? 0),
    ),
    OverallFactor.restingHeartRate => l10n.overallValueResting(
      format.bpm(inputs.restingHeartRate ?? 0),
    ),
    OverallFactor.sleepDuration => l10n.overallValueSleep(
      format.duration(
        Duration(minutes: ((inputs.sleepHours ?? 0) * 60).round()),
      ),
    ),
    OverallFactor.sleepRegularity => l10n.overallValueRegularity(
      format.integer(inputs.sleepRegularity ?? 0),
    ),
    OverallFactor.movement => l10n.overallValueMovement(
      format.integer(inputs.weeklyMinutes ?? 0),
      format.decimal(inputs.strengthPerWeek, digits: 1),
      format.integer(inputs.dailySteps ?? 0),
    ),
    OverallFactor.body => _bodyText(format, inputs, hidden: hidden),
  };
}

String _bodyText(
  MetricFormat format,
  OverallInputs inputs, {
  required bool hidden,
}) {
  final l10n = format.l10n;
  if (hidden) return l10n.overallValueHidden;
  final waist = inputs.waistToHeight;
  if (waist != null) {
    return l10n.overallValueWaist(format.decimal(waist, digits: 2));
  }
  return l10n.overallValueBmi(format.decimal(inputs.bmi ?? 0, digits: 1));
}

typedef _Copy = ({
  String title,
  String what,
  String rule,
  String source,
  String ours,
  String limits,
});

_Copy _copy(MetricFormat format, OverallFactor factor, OverallInputs inputs) {
  final l10n = format.l10n;
  final points = format.integer(factor.weight);
  String two(double value) => format.decimal(value, digits: 2);
  return switch (factor) {
    OverallFactor.fitness => (
      title: l10n.overallFactorFitness,
      what: l10n.overallWhatFitness,
      rule: l10n.overallRuleFitness(format.integer(fitnessFullPercentile)),
      source: l10n.overallSourceFitness,
      ours: l10n.overallOursFitness(points),
      limits: l10n.overallLimitsFitness,
    ),
    OverallFactor.restingHeartRate => (
      title: l10n.overallFactorResting,
      what: l10n.overallWhatResting,
      rule: l10n.overallRuleResting(
        format.integer(overallRestingZeroAt),
        format.integer(overallRestingFullAt),
      ),
      source: l10n.overallSourceResting,
      ours: l10n.overallOursResting(points),
      limits: l10n.overallLimitsResting,
    ),
    OverallFactor.sleepDuration => (
      title: l10n.overallFactorSleepDuration,
      what: l10n.overallWhatSleepDuration,
      rule: l10n.overallRuleSleepDuration(
        format.integer(sleepHoursZeroAt),
        format.integer(sleepHoursFullAt),
      ),
      source: l10n.overallSourceSleepDuration,
      ours: l10n.overallOursSleepDuration(points),
      limits: l10n.overallLimitsSleepDuration,
    ),
    OverallFactor.sleepRegularity => (
      title: l10n.overallFactorSleepRegularity,
      what: l10n.overallWhatSleepRegularity,
      rule: l10n.overallRuleSleepRegularity(
        format.integer(sleepRegularityZeroAt),
        format.integer(sleepRegularityFullAt),
      ),
      source: l10n.overallSourceSleepRegularity,
      ours: l10n.overallOursSleepRegularity(points),
      limits: l10n.overallLimitsSleepRegularity,
    ),
    OverallFactor.movement => (
      title: l10n.overallFactorMovement,
      what: l10n.overallWhatMovement,
      rule: l10n.overallRuleMovement(
        format.integer(movementMinutesTarget),
        format.integer(movementMinutesCeiling),
        format.integer(movementStrengthTarget),
        format.integer(movementStepsZeroAt),
        format.integer(
          inputs.olderAdult ? movementStepsFullAtOlder : movementStepsFullAt,
        ),
      ),
      source: l10n.overallSourceMovement,
      ours: l10n.overallOursMovement(points),
      limits: l10n.overallLimitsMovement,
    ),
    OverallFactor.body when inputs.waistToHeight == null => (
      title: l10n.overallFactorBody,
      what: l10n.overallWhatBodyBmi,
      rule: l10n.overallRuleBodyBmi(
        format.integer(bmiFullAt),
        format.integer(bmiZeroAt),
        format.decimal(bmiFloor, digits: 1),
      ),
      source: l10n.overallSourceBodyBmi,
      ours: l10n.overallOursBody(points),
      limits: l10n.overallLimitsBody,
    ),
    OverallFactor.body => (
      title: l10n.overallFactorBody,
      what: l10n.overallWhatBody,
      rule: l10n.overallRuleBody(
        two(waistToHeightFullAt),
        two(waistToHeightZeroAt),
        two(waistToHeightFloor),
      ),
      source: l10n.overallSourceBody,
      ours: l10n.overallOursBody(points),
      limits: l10n.overallLimitsBody,
    ),
  };
}

String? _window(
  AppLocalizations l10n,
  MetricFormat format,
  OverallFactor factor,
) => switch (factor) {
  OverallFactor.fitness => l10n.overallSheetFitnessWindow(
    format.integer(fitnessWindowDays),
  ),
  OverallFactor.body => l10n.overallSheetBodyWindow,
  OverallFactor.sleepRegularity => l10n.overallSheetWindowPairs(
    format.integer(overallWindowDays),
    format.integer(sleepRegularityMinPairs),
  ),
  _ => l10n.overallSheetWindowBody(
    format.integer(overallWindowDays),
    format.integer(overallMinDays),
  ),
};

Future<void> showOverallEvidence(
  BuildContext context, {
  required OverallFactor factor,
  required OverallInputs inputs,
  required Contribution<OverallFactor>? earned,
  required bool hidden,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.of(context).surface,
  builder: (context) => SafeArea(
    child: OverallEvidenceSheet(
      factor: factor,
      inputs: inputs,
      earned: earned,
      hidden: hidden,
    ),
  ),
);

class OverallEvidenceSheet extends StatelessWidget {
  const new({
    required this.factor,
    required this.inputs,
    required this.earned,
    required this.hidden,
    super.key,
  });

  final OverallFactor factor;
  final OverallInputs inputs;
  final Contribution<OverallFactor>? earned;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final theme = Theme.of(context).textTheme;
    final copy = _copy(format, factor, inputs);
    final earned = this.earned;
    final window = _window(l10n, format, factor);
    final movement = factor == OverallFactor.movement
        ? inputs.movementPoints
        : null;
    final secret = overallSecret(factor, hidden: hidden);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        key: OverallEvidenceKeys.sheet,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              copy.title,
              key: OverallEvidenceKeys.title,
              style: theme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (earned != null && !secret) ...[
              const SizedBox(height: 2),
              CaptionText(
                key: OverallEvidenceKeys.points,
                l10n.dayScoreReceiptPoints(
                  l10n.dayScoreReceiptOf(
                    format.points(earned.points),
                    format.integer(earned.weight),
                  ),
                ),
              ),
            ],
            _Section(title: l10n.overallSheetWhat, body: copy.what),
            _Section(
              key: OverallEvidenceKeys.yours,
              title: l10n.overallSheetYours,
              body: earned == null
                  ? l10n.overallGone(factor.weight.round())
                  : overallValueText(format, factor, inputs, hidden: hidden),
            ),
            if (movement != null)
              Padding(
                key: OverallEvidenceKeys.parts,
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Part(
                      label: l10n.overallPartMinutes,
                      earned: movement.minutes,
                      weight: movementMinutesWeight,
                    ),
                    _Part(
                      label: l10n.overallPartStrength,
                      earned: movement.strength,
                      weight: movementStrengthWeight,
                    ),
                    _Part(
                      label: l10n.overallPartSteps,
                      earned: movement.steps,
                      weight: movementStepsWeight,
                    ),
                  ],
                ),
              ),
            if (window != null)
              _Section(
                key: OverallEvidenceKeys.window,
                title: l10n.overallSheetWindow,
                body: window,
              ),
            _Section(
              key: OverallEvidenceKeys.rule,
              title: l10n.overallSheetRule,
              body: copy.rule,
            ),
            _Section(title: l10n.overallSheetSource, body: copy.source),
            _Section(title: l10n.overallSheetOurs, body: copy.ours),
            _Section(title: l10n.overallSheetLimits, body: copy.limits),
            const SizedBox(height: 16),
            CaptionText(
              key: OverallEvidenceKeys.association,
              '${l10n.overallSheetAssociation} ${l10n.metricEstimateNote}',
            ),
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

class _Part extends StatelessWidget {
  const new({required this.label, required this.earned, required this.weight});

  final String label;
  final double earned;
  final double weight;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        children: [
          BodyText(label),
          BodyText(
            format.l10n.dayScoreReceiptOf(
              format.points(earned),
              format.integer(weight),
            ),
          ),
        ],
      ),
    );
  }
}
