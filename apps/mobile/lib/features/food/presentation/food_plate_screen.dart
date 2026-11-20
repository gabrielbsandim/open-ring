import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/food_plate.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';

abstract final class FoodPlateKeys {
  static const lead = Key('food_plate_lead');
  static const softModeCard = Key('food_plate_soft_mode_card');
  static const summaryCard = Key('food_plate_summary_card');
  static const score = Key('food_plate_score');
  static const weeksCard = Key('food_plate_weeks_card');
  static const ruleCard = Key('food_plate_rule_card');
  static const ruleExpression = Key('food_plate_rule_expression');
  static const oursCard = Key('food_plate_ours_card');

  static Key component(int index) => Key('food_plate_component_$index');
  static Key weekRow(LocalDate monday) => Key('food_plate_week_${monday.iso}');
}

String _rampLine(
  MetricFormat f,
  double weight,
  String input,
  double zero,
  double full,
  double pts, {
  int rangeDigits = 1,
}) =>
    '${f.integer(weight)} × ($input, ${f.decimal(zero, digits: rangeDigits)}, '
    '${f.decimal(full, digits: rangeDigits)}) = ${f.decimal(pts, digits: 2)}';

String foodPlateExpression(MetricFormat f, PlateResult plate) {
  final l = f.l10n;
  if (plate is PlatePattern) {
    final s7 = plate.sugaryDays * 7 / plate.completeDays;
    final a7 = plate.drinks * 7 / plate.completeDays;
    return l.foodPlateRulePattern(
      plate.mains,
      _rampLine(
        f,
        plateProteinWeight,
        '${plate.protein}/${plate.mains}',
        plateProteinZero,
        plateProteinFull,
        plate.points[0],
      ),
      _rampLine(
        f,
        plateVegWeight,
        '${plate.veg}/${plate.mains}',
        plateVegZero,
        plateVegFull,
        plate.points[1],
      ),
      _rampLine(
        f,
        plateProcessedWeight,
        '1 - ${plate.processed}/${plate.mains}',
        plateProcessedZero,
        plateProcessedFull,
        plate.points[2],
      ),
      _rampLine(
        f,
        plateSugarWeight,
        f.decimal(s7, digits: 2),
        plateSugarZero,
        plateSugarFull,
        plate.points[3],
        rangeDigits: 0,
      ),
      _rampLine(
        f,
        plateDrinksWeight,
        f.decimal(a7, digits: 2),
        plateDrinksZero,
        plateDrinksFull,
        plate.points[4],
        rangeDigits: 0,
      ),
      f.decimal(plate.score, digits: 1),
    );
  }
  return l.foodPlateRuleGeneral(
    f.decimal(plateProteinZero, digits: 1),
    f.decimal(plateProteinFull, digits: 1),
    f.decimal(plateVegZero, digits: 1),
    f.decimal(plateVegFull, digits: 1),
    f.decimal(plateProcessedZero, digits: 1),
    f.decimal(plateProcessedFull, digits: 1),
    f.integer(plateSugarZero),
    f.integer(plateSugarFull),
    f.integer(plateDrinksZero),
    f.integer(plateDrinksFull),
    f.decimal(plateDrinksOneToTwo, digits: 1),
    f.integer(plateDrinksThreeOrMore),
  );
}

class FoodPlateScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = MetricFormat.of(context);
    final l = f.l10n;
    if (!ref.watch(foodEnabledProvider)) {
      return AppPage(title: l.foodPlateTitle, children: const []);
    }
    final plate = ref.watch(foodPlateProvider);
    return AppPage(
      title: l.foodPlateTitle,
      children: _body(
        plate,
        f,
        Theme.of(context).textTheme,
        AppColors.of(context),
      ),
    );
  }

  List<Widget> _body(
    AsyncValue<FoodPlateView> plate,
    MetricFormat f,
    TextTheme t,
    AppColors c,
  ) {
    final l = f.l10n;
    if (plate.hasError) return [BodyText(l.metricLoadError)];
    if (!plate.hasValue) return const [SizedBox(height: 96)];
    final view = plate.requireValue;
    if (view.softMode) {
      return [
        MetricCard(
          key: FoodPlateKeys.softModeCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccentTitle(title: l.foodWeekSoftTitle, accent: c.activity),
              const SizedBox(height: 8),
              BodyText(l.foodWeekSoftBody),
            ],
          ),
        ),
      ];
    }
    final current = view.current;
    final range = l.metricTimeRange(
      f.monthDay(current.monday),
      f.monthDay(current.sunday),
    );
    return [
      BodyText(l.foodPlateLead(range), key: FoodPlateKeys.lead),
      const SizedBox(height: 16),
      _summaryCard(current.plate, f, t, c),
      const SizedBox(height: cardGap),
      _weeksCard(view.weeks, f, t, c),
      const SizedBox(height: cardGap),
      _ruleCard(current.plate, f, t, c),
      const SizedBox(height: cardGap),
      ModuleFactsCard(
        key: FoodPlateKeys.oursCard,
        title: l.dayScoreFormulaSourceOursTitle,
        icon: Icons.edit_outlined,
        facts: [l.foodPlateOurs1, l.foodPlateOurs2],
      ),
    ];
  }
}

Widget _summaryCard(
  PlateResult plate,
  MetricFormat f,
  TextTheme t,
  AppColors c,
) {
  final l = f.l10n;
  if (plate is PlateBuilding) {
    return MetricCard(
      key: FoodPlateKeys.summaryCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BodyText(
            l.foodPlateBuilding(
              plateMinCompleteDays,
              plateMinMains,
              plate.completeDays,
              plate.mains,
            ),
          ),
          const SizedBox(height: 10),
          CaptionText(l.foodPlateDisclaimer),
        ],
      ),
    );
  }
  final p = plate as PlatePattern;
  final rows = [
    (
      '${l.foodPlateCompProtein} · ${l.foodPlateCountOf(p.protein, p.mains)}',
      l.foodPlatePointsOf(
        f.decimal(p.points[0], digits: 1),
        f.integer(plateProteinWeight),
      ),
    ),
    (
      '${l.foodPlateCompVeg} · ${l.foodPlateCountOf(p.veg, p.mains)}',
      l.foodPlatePointsOf(
        f.decimal(p.points[1], digits: 1),
        f.integer(plateVegWeight),
      ),
    ),
    (
      '${l.foodPlateCompProcessed} · ${l.foodPlateCountOf(p.mains - p.processed, p.mains)}',
      l.foodPlatePointsOf(
        f.decimal(p.points[2], digits: 1),
        f.integer(plateProcessedWeight),
      ),
    ),
    (
      '${l.foodPlateCompSugar} · ${l.foodPlateDaysOf(p.sugaryDays, p.completeDays)}',
      l.foodPlatePointsOf(
        f.decimal(p.points[3], digits: 1),
        f.integer(plateSugarWeight),
      ),
    ),
    (
      '${l.foodAlcoholLabel} · ${l.foodPlateDrinks(f.points(p.drinks))}',
      l.foodPlatePointsOf(
        f.decimal(p.points[4], digits: 1),
        f.integer(plateDrinksWeight),
      ),
    ),
  ];
  return MetricCard(
    key: FoodPlateKeys.summaryCard,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              f.decimal(p.score, digits: 1),
              key: FoodPlateKeys.score,
              style: numberStyle(t.headlineMedium),
            ),
            CaptionText(l.foodPlateOfTen),
          ],
        ),
        const SizedBox(height: 4),
        CaptionText(l.foodPlateMainsInDays(p.mains, p.completeDays)),
        const SizedBox(height: 12),
        for (var i = 0; i < rows.length; i++) ...[
          Divider(height: 1, color: c.surfaceBorder),
          Padding(
            key: FoodPlateKeys.component(i),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 2,
              children: [
                Text(rows[i].$1, style: t.bodyMedium),
                Text(rows[i].$2, style: numberStyle(t.bodyMedium)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 6),
        CaptionText(l.foodPlateDisclaimer),
      ],
    ),
  );
}

Widget _weeksCard(
  List<FoodPlateWeek> weeks,
  MetricFormat f,
  TextTheme t,
  AppColors c,
) {
  final l = f.l10n;
  return MetricCard(
    key: FoodPlateKeys.weeksCard,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l.foodPlateWeeksTitle,
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        for (final w in weeks) ...[
          Divider(height: 1, color: c.surfaceBorder),
          Padding(
            key: FoodPlateKeys.weekRow(w.monday),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 2,
              children: [
                Text(
                  l.metricTimeRange(f.monthDay(w.monday), f.monthDay(w.sunday)),
                  style: t.bodyMedium,
                ),
                Text(
                  switch (w.plate) {
                    final PlatePattern p => f.decimal(p.score, digits: 1),
                    final PlateBuilding b => l.foodPlateWeekShort(
                      b.completeDays,
                      b.mains,
                    ),
                  },
                  style: numberStyle(
                    t.bodyMedium,
                    color: w.plate is PlatePattern
                        ? c.textPrimary
                        : c.textLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 6),
        CaptionText(l.foodPlateWeeksNote(plateMinCompleteDays, plateMinMains)),
      ],
    ),
  );
}

Widget _ruleCard(PlateResult plate, MetricFormat f, TextTheme t, AppColors c) {
  final l = f.l10n;
  return MetricCard(
    key: FoodPlateKeys.ruleCard,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l.foodPlateRuleTitle,
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceInner,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              foodPlateExpression(f, plate),
              key: FoodPlateKeys.ruleExpression,
              style: numberStyle(t.bodySmall),
            ),
          ),
        ),
        const SizedBox(height: 10),
        CaptionText(l.foodPlateRuleNote),
      ],
    ),
  );
}
