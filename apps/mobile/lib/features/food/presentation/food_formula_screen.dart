import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/food/presentation/food_plate_screen.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';

abstract final class FoodFormulaKeys {
  static const intro = Key('food_formula_intro');
  static const meal = Key('food_formula_meal');
  static const complete = Key('food_formula_complete');
  static const timing = Key('food_formula_timing');
  static const comparisons = Key('food_formula_comparisons');
  static const plate = Key('food_formula_plate');
  static const sources = Key('food_formula_sources');
  static const ours = Key('food_formula_ours');
  static const unchecked = Key('food_formula_unchecked');
  static const cannot = Key('food_formula_cannot');
  static const estimate = Key('food_formula_estimate');
}

class FoodFormulaLink extends StatelessWidget {
  const new({required this.buttonKey, super.key});

  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    final l = MetricFormat.of(context).l10n;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: buttonKey,
        onPressed: () {
          final router = GoRouter.maybeOf(context);
          if (router != null) unawaited(router.push(AppPaths.foodFormula));
        },
        icon: const Icon(Icons.receipt_long_outlined),
        label: Text(l.formulaLink),
      ),
    );
  }
}

String _clockOfMinute(MetricFormat f, int minute) =>
    f.clock(DateTime.utc(2026, 1, 1, minute ~/ 60, minute % 60), Duration.zero);

class FoodFormulaScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final f = MetricFormat.of(context);
    final l = f.l10n;
    final t = Theme.of(context).textTheme;
    final c = AppColors.of(context);
    return AppPage(
      title: l.formulaLink,
      children: [
        BodyText(l.foodFormulaIntro, key: FoodFormulaKeys.intro),
        const SizedBox(height: 16),
        _formulaCard(
          FoodFormulaKeys.meal,
          l.foodFormulaMealTitle,
          t,
          c,
          body: l.foodFormulaMealBody(_clockOfMinute(f, foodDayStartHour * 60)),
          expr: l.foodFormulaMealSlots(
            _clockOfMinute(f, mealSlotLunchMinute),
            _clockOfMinute(f, mealSlotAfternoonMinute),
            _clockOfMinute(f, mealSlotDinnerMinute),
            _clockOfMinute(f, mealSlotSupperMinute),
          ),
        ),
        const SizedBox(height: cardGap),
        _formulaCard(
          FoodFormulaKeys.complete,
          l.foodFormulaCompleteTitle,
          t,
          c,
          body: l.foodDayCompleteNote,
        ),
        const SizedBox(height: cardGap),
        _formulaCard(
          FoodFormulaKeys.timing,
          l.foodTimingTitle,
          t,
          c,
          expr: l.foodFormulaTimingExpr,
        ),
        const SizedBox(height: cardGap),
        _formulaCard(
          FoodFormulaKeys.comparisons,
          l.foodFormulaCompTitle,
          t,
          c,
          body: l.foodFormulaCompBody(foodCompareNights, foodPairMaxDays),
          expr: l.foodFormulaCompExpr(
            alcoholMinPairs,
            foodMinPairs,
            f.bpm(heartRateMeaningful),
            f.percent(hrvMeaningfulPercent),
            f.duration(Duration(minutes: onsetMeaningfulMinutes.round())),
          ),
          note: l.foodFormulaCompNote,
        ),
        const SizedBox(height: cardGap),
        _formulaCard(
          FoodFormulaKeys.plate,
          l.foodPlateTitle,
          t,
          c,
          expr: foodPlateExpression(
            f,
            const PlateBuilding(completeDays: 0, mains: 0),
          ),
          note:
              '${l.foodPlateWeeksNote(plateMinCompleteDays, plateMinMains)} '
              '${l.foodPlateRuleNote}',
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: FoodFormulaKeys.sources,
          title: l.effortFormulaSourcesTitle,
          icon: Icons.check_rounded,
          facts: [l.foodFormulaSource1],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: FoodFormulaKeys.ours,
          title: l.dayScoreFormulaSourceOursTitle,
          icon: Icons.edit_outlined,
          facts: [
            l.foodFormulaOurs1,
            l.foodFormulaOurs2(foodCompareNights, foodPairMaxDays),
            l.foodPlateOurs1,
            l.foodPlateOurs2,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: FoodFormulaKeys.unchecked,
          title: l.effortFormulaUncheckedTitle,
          icon: Icons.schedule,
          facts: [
            l.foodFormulaUnchecked1,
            l.foodFormulaUnchecked2,
            l.foodFormulaUnchecked3,
            l.foodFormulaUnchecked4,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: FoodFormulaKeys.cannot,
          title: l.effortFormulaCannotTitle,
          icon: Icons.block,
          facts: [
            l.foodFormulaCannot1,
            l.foodFormulaCannot2,
            l.foodFormulaCannot3,
          ],
        ),
        const SizedBox(height: 16),
        CaptionText(l.metricEstimateNote, key: FoodFormulaKeys.estimate),
      ],
    );
  }
}

Widget _formulaCard(
  Key key,
  String title,
  TextTheme t,
  AppColors c, {
  String? body,
  String? expr,
  String? note,
}) => MetricCard(
  key: key,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AccentTitle(title: title, accent: c.textPrimary),
      if (body != null) ...[const SizedBox(height: 8), BodyText(body)],
      if (expr != null) ...[
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceInner,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(expr, style: numberStyle(t.bodySmall)),
          ),
        ),
      ],
      if (note != null) ...[const SizedBox(height: 10), CaptionText(note)],
    ],
  ),
);
