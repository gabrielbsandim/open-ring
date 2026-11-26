import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/open_score/presentation/day_score_formula_screen.dart';

abstract final class TrajectoryFormulaKeys {
  static const projections = Key('trajectory_formula_projections');
  static const protections = Key('trajectory_formula_protections');
  static const cannot = Key('trajectory_formula_cannot');
}

class TrajectoryFormulaScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return AppPage(
      title: l10n.formulaLink,
      children: [
        BodyText(l10n.trajectoryFormulaIntro),
        const SizedBox(height: 16),
        MetricCard(
          key: TrajectoryFormulaKeys.projections,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccentTitle(
                title: l10n.trajectoryProjectionsTitle,
                accent: AppColors.of(context).textPrimary,
              ),
              const SizedBox(height: 4),
              BodyText(l10n.trajectoryFormulaProjections),
            ],
          ),
        ),
        const SizedBox(height: cardGap),
        DayScoreListCard(
          key: TrajectoryFormulaKeys.protections,
          title: l10n.trajectoryFormulaProtectionsTitle,
          lines: [
            l10n.trajectoryFormulaProtection1(
              format.decimal(trajectoryFastLossPercent),
            ),
            l10n.trajectoryFormulaProtection2(
              format.decimal(bmiFloor, digits: 1),
            ),
            l10n.trajectoryFormulaProtection3,
            l10n.trajectoryFormulaProtection4(format.integer(energyAdultAge)),
            l10n.trajectoryFormulaProtection5,
          ],
        ),
        const SizedBox(height: cardGap),
        DayScoreListCard(
          key: TrajectoryFormulaKeys.cannot,
          title: l10n.effortFormulaCannotTitle,
          lines: [
            l10n.trajectoryFormulaCannot1,
            l10n.trajectoryFormulaCannot2,
            l10n.trajectoryFormulaCannot3,
            l10n.trajectoryFormulaCannot4,
            l10n.trajectoryFormulaCannot5,
          ],
        ),
        const SizedBox(height: 16),
        CaptionText(l10n.trajectoryFormulaFoot),
      ],
    );
  }
}
