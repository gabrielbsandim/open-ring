import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/presentation/energy_evidence_sheet.dart';
import 'package:open_ring/features/open_score/presentation/day_score_formula_screen.dart';

abstract final class EnergyFormulaKeys {
  static const margins = Key('energy_formula_margins');
  static const sources = Key('energy_formula_sources');

  static Key rule(EnergyEvidence kind) => Key('energy_formula_${kind.name}');
}

const _mifflin =
    'Mifflin MD, St Jeor ST, Hill LA, Scott BJ, Daugherty SA, Koh YO. '
    'A new predictive equation for resting energy expenditure in healthy '
    'individuals. Am J Clin Nutr. 1990.';
const _frankenfield =
    'Frankenfield D, Roth-Yousey L, Compher C. Comparison of predictive '
    'equations for resting metabolic rate in healthy nonobese and obese '
    'adults: a systematic review. J Am Diet Assoc. 2005.';
const _fao =
    'FAO, WHO, UNU. Human energy requirements: report of a joint expert '
    'consultation, Rome, 2001.';
const _shcherbina =
    'Shcherbina A, et al. Accuracy in wrist-worn, sensor-based measurements '
    'of heart rate and energy expenditure in a diverse cohort. '
    'J Pers Med. 2017.';

const List<String> energyFormulaSources = [
  _mifflin,
  _frankenfield,
  _fao,
  _shcherbina,
];

class EnergyFormulaScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    if (ref.watch(energyGateProvider) != EnergyGate.on) {
      return AppPage(title: l10n.formulaLink, children: const []);
    }
    String percent(double share) => format.integer(share * 100);
    return AppPage(
      title: l10n.formulaLink,
      children: [
        BodyText(l10n.energyFormulaIntro),
        const SizedBox(height: 16),
        for (final kind in EnergyEvidence.values) ...[
          _Rule(kind: kind),
          const SizedBox(height: cardGap),
        ],
        DayScoreListCard(
          key: EnergyFormulaKeys.margins,
          title: l10n.energyFormulaMarginsTitle,
          lines: [
            l10n.energyFormulaMargin1(
              percent(energyRestingMargin),
              percent(energyDayMargin),
              format.integer(energyRangeStep),
            ),
            l10n.energyFormulaMargin2,
          ],
        ),
        const SizedBox(height: cardGap),
        const _Sources(),
        const SizedBox(height: 16),
        CaptionText(l10n.energyFixedNote),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const new({required this.kind});

  final EnergyEvidence kind;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final copy = energyEvidenceCopy(format, kind);
    return MetricCard(
      key: EnergyFormulaKeys.rule(kind),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: copy.title,
            accent: AppColors.of(context).textPrimary,
          ),
          EnergyEvidenceSection(title: l10n.overallSheetRule, body: copy.rule),
          EnergyEvidenceSection(
            title: l10n.overallSheetSource,
            body: copy.source,
          ),
          EnergyEvidenceSection(title: l10n.overallSheetOurs, body: copy.ours),
          EnergyEvidenceSection(
            title: l10n.overallSheetLimits,
            body: copy.limits,
          ),
        ],
      ),
    );
  }
}

class _Sources extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return MetricCard(
      key: EnergyFormulaKeys.sources,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: l10n.dayScoreFormulaSourcesTitle,
            accent: colors.textPrimary,
          ),
          for (final source in energyFormulaSources)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: CaptionText(source),
            ),
        ],
      ),
    );
  }
}
