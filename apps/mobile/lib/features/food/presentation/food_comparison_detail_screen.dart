import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/food/application/food_comparisons.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/presentation/food_comparisons_screen.dart';
import 'package:open_ring/features/food/presentation/food_formula_screen.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';

abstract final class FoodComparisonDetailKeys {
  static const lead = Key('food_comp_detail_lead');
  static const verdictCard = Key('food_comp_detail_verdict');
  static const alsoCard = Key('food_comp_detail_also');
  static const pairsCard = Key('food_comp_detail_pairs');
  static const ruleCard = Key('food_comp_detail_rule');
  static const ruleExpression = Key('food_comp_detail_rule_expr');
  static const cannotCard = Key('food_comp_detail_cannot');
  static const formulaLink = Key('food_comp_detail_formula_link');
  static const notFound = Key('food_comp_detail_not_found');

  static Key pairRow(int index) => Key('food_comp_detail_pair_$index');
}

double _meaningful(NightOutcome outcome) => switch (outcome) {
  NightOutcome.heartRate => heartRateMeaningful,
  NightOutcome.hrv => hrvMeaningfulPercent,
  NightOutcome.onset => onsetMeaningfulMinutes,
};

int _minimumPairs(FoodComparisonItem item) =>
    item.alcoholLink ? alcoholMinPairs : foodMinPairs;

String _signedOutcome(
  MetricFormat f,
  NightOutcome outcome,
  double value, {
  int? digits,
}) {
  final l = f.l10n;
  final d = digits ?? (value.abs() > 0 && value.abs() < 1 ? 1 : 0);
  final text = f.signed(value, digits: d);
  return switch (outcome) {
    NightOutcome.heartRate => l.metricBpm(text),
    NightOutcome.hrv => l.metricPercent(text),
    NightOutcome.onset => l.metricDurationMinutes(0).replaceFirst('0', text),
  };
}

class FoodComparisonDetailScreen extends ConsumerWidget {
  const new({required this.link, super.key});

  final FoodLink? link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = MetricFormat.of(context);
    final l = f.l10n;
    if (!ref.watch(foodEnabledProvider)) {
      return AppPage(title: l.foodTabComparisons, children: const []);
    }
    final selected = link;
    if (selected == null) {
      return AppPage(
        title: l.foodTabComparisons,
        children: [
          BodyText(
            l.foodCompDetailNotFound,
            key: FoodComparisonDetailKeys.notFound,
          ),
        ],
      );
    }
    final state = ref.watch(foodComparisonsProvider);
    final t = Theme.of(context).textTheme;
    final c = AppColors.of(context);
    return AppPage(
      title: l.foodCompDetailTitle(foodLinkTitle(f, selected)),
      children: _body(state, selected, f, t, c),
    );
  }

  List<Widget> _body(
    AsyncValue<FoodComparisonsView> state,
    FoodLink selected,
    MetricFormat f,
    TextTheme t,
    AppColors c,
  ) {
    final l = f.l10n;
    if (state.hasError) return [BodyText(l.metricLoadError)];
    if (!state.hasValue) return const [SizedBox(height: 96)];
    final view = state.requireValue;
    final item = _findItem(view.items, selected);
    if (item == null) {
      return [
        BodyText(
          l.foodCompDetailNotFound,
          key: FoodComparisonDetailKeys.notFound,
        ),
      ];
    }
    final range = l.metricTimeRange(
      f.monthDay(view.firstNight),
      f.monthDay(view.lastNight),
    );
    return [
      BodyText(
        l.foodCompDetailLead(range, f.date(view.updatedMonday)),
        key: FoodComparisonDetailKeys.lead,
      ),
      const SizedBox(height: cardGap),
      _verdictCard(item, f, t, c),
      if (item.lead case final LinkDecided decided) ...[
        const SizedBox(height: cardGap),
        _alsoCard(item, f, c),
        const SizedBox(height: cardGap),
        _pairsCard(item, f, t, c),
        if (item.leadSd != null && item.leadT99 != null) ...[
          const SizedBox(height: cardGap),
          _ruleCard(item, decided, f, t, c),
        ],
      ],
      const SizedBox(height: cardGap),
      ModuleFactsCard(
        key: FoodComparisonDetailKeys.cannotCard,
        title: l.effortFormulaCannotTitle,
        icon: Icons.block,
        facts: [
          '${l.foodFormulaCannot2} ${l.foodCompAlt(item.link.name)}',
          l.foodCompCannotTagged,
          l.foodCompCannotRing,
        ],
      ),
      const SizedBox(height: 8),
      const FoodFormulaLink(buttonKey: FoodComparisonDetailKeys.formulaLink),
    ];
  }
}

FoodComparisonItem? _findItem(
  List<FoodComparisonItem> items,
  FoodLink selected,
) {
  for (final item in items) {
    if (item.link == selected) return item;
  }
  return null;
}

Widget _verdictCard(
  FoodComparisonItem item,
  MetricFormat f,
  TextTheme t,
  AppColors c,
) {
  final l = f.l10n;
  final why = switch (item.lead) {
    LinkPattern() => l.foodCompPatternWhy(l.foodCompAlt(item.link.name)),
    final LinkNoClearDifference d => l.foodCompNoneWhy(
      d.pairs,
      foodFormatMagnitude(f, item.leadOutcome, _meaningful(item.leadOutcome)),
    ),
    final LinkCollecting col => l.foodCompCollectingWhy(col.minimum),
  };
  return MetricCard(
    key: FoodComparisonDetailKeys.verdictCard,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        foodComparisonHeader(
          foodOutcomeLabel(l, item.leadOutcome),
          foodCompTagText(l, item.lead),
          t,
          c,
        ),
        const SizedBox(height: 10),
        BodyText(foodLeadSummaryText(f, item.leadOutcome, item.lead)),
        const SizedBox(height: 8),
        CaptionText(why),
      ],
    ),
  );
}

Widget _alsoCard(FoodComparisonItem item, MetricFormat f, AppColors c) {
  final l = f.l10n;
  final name = foodOutcomeLabel(l, item.alsoOutcome);
  final text = switch (item.also) {
    final LinkPattern p => l.foodCompAlsoPattern(
      name,
      foodCompDeltaText(f, item.alsoOutcome, p.mean),
      foodPatternRangeText(f, item.alsoOutcome, p.low, p.high),
      p.pairs,
    ),
    final LinkNoClearDifference d => l.foodCompAlsoNone(
      name,
      l.metricTimeRange(
        _signedOutcome(f, item.alsoOutcome, d.low),
        _signedOutcome(f, item.alsoOutcome, d.high),
      ),
      d.pairs,
    ),
    final LinkCollecting col => l.foodCompAlsoCollecting(
      name,
      col.pairs,
      col.minimum,
    ),
  };
  return MetricCard(
    key: FoodComparisonDetailKeys.alsoCard,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccentTitle(title: l.foodCompAlsoTitle, accent: c.textPrimary),
        const SizedBox(height: 8),
        BodyText(text),
      ],
    ),
  );
}

Widget _pairsCard(
  FoodComparisonItem item,
  MetricFormat f,
  TextTheme t,
  AppColors c,
) {
  final l = f.l10n;
  final newestFirst = item.leadPairs.reversed.toList(growable: false);
  return MetricCard(
    key: FoodComparisonDetailKeys.pairsCard,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccentTitle(title: l.foodCompPairsTitle, accent: c.textPrimary),
        const SizedBox(height: 4),
        CaptionText(l.foodCompPairsNote),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(flex: 4, child: CaptionText(l.foodCompPairsWith)),
            const SizedBox(width: 8),
            Expanded(flex: 4, child: CaptionText(l.foodCompPairsWithout)),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Text(
                l.foodCompPairsDiff,
                style: t.bodySmall?.copyWith(color: c.textSecondary),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < newestFirst.length; i++) ...[
          Divider(height: 1, color: c.surfaceBorder),
          Padding(
            key: FoodComparisonDetailKeys.pairRow(i),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: _pairCell(
                    f,
                    t,
                    newestFirst[i].exposedDay,
                    _pairValue(
                      f,
                      item.leadOutcome,
                      hr: newestFirst[i].exposedHeartRate,
                      onset: newestFirst[i].exposedOnset,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: _pairCell(
                    f,
                    t,
                    newestFirst[i].controlDay,
                    _pairValue(
                      f,
                      item.leadOutcome,
                      hr: newestFirst[i].controlHeartRate,
                      onset: newestFirst[i].controlOnset,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Text(
                    f.signed(newestFirst[i].diff),
                    style: numberStyle(t.bodySmall),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _pairCell(MetricFormat f, TextTheme t, LocalDate day, String value) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CaptionText(f.date(day)),
        Text(value, style: numberStyle(t.bodySmall)),
      ],
    );

String _pairValue(
  MetricFormat f,
  NightOutcome outcome, {
  double? hr,
  DateTime? onset,
}) {
  if (outcome == NightOutcome.onset && onset != null) {
    return f.clock(onset, Duration.zero);
  }
  if (hr != null) return f.bpm(hr);
  return f.l10n.metricNoReading;
}

Widget _ruleCard(
  FoodComparisonItem item,
  LinkDecided lead,
  MetricFormat f,
  TextTheme t,
  AppColors c,
) {
  final l = f.l10n;
  final expr = l.foodCompRuleExpr(
    lead.pairs,
    _minimumPairs(item),
    _signedOutcome(f, item.leadOutcome, lead.mean, digits: 1),
    f.decimal(item.leadSd!, digits: 1),
    lead.pairs - 1,
    f.decimal(item.leadT99!, digits: 3),
    _signedOutcome(f, item.leadOutcome, lead.low, digits: 1),
    _signedOutcome(f, item.leadOutcome, lead.high, digits: 1),
    foodFormatMagnitude(f, item.leadOutcome, _meaningful(item.leadOutcome)),
  );
  return MetricCard(
    key: FoodComparisonDetailKeys.ruleCard,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccentTitle(title: l.foodPlateRuleTitle, accent: c.textPrimary),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceInner,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              expr,
              key: FoodComparisonDetailKeys.ruleExpression,
              style: numberStyle(t.bodySmall),
            ),
          ),
        ),
        const SizedBox(height: 10),
        CaptionText(
          l.foodCompRuleNote(
            item.alcoholLink ? 'yes' : 'no',
            foodPairMaxDays,
            l.moduleOpenScoreName,
          ),
        ),
      ],
    ),
  );
}
