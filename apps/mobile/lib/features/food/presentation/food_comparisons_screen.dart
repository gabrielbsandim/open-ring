import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/food/application/food_comparisons.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/presentation/food_formula_screen.dart';
import 'package:open_ring/features/food/presentation/food_week_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class FoodComparisonsKeys {
  static const lead = Key('food_comparisons_lead');
  static const regularityCard = Key('food_comparisons_regularity_card');
  static const foot = Key('food_comparisons_foot');
  static const formulaLink = Key('food_comparisons_formula_link');

  static Key card(FoodLink link) => Key('food_comp_card_${link.name}');
  static Key tag(FoodLink link) => Key('food_comp_tag_${link.name}');
  static Key progress(FoodLink link) => Key('food_comp_progress_${link.name}');
}

String _clockOfMinute(MetricFormat f, int minute) =>
    f.clock(DateTime.utc(2026, 1, 1, minute ~/ 60, minute % 60), Duration.zero);

String foodLinkTitle(MetricFormat f, FoodLink link) {
  final l = f.l10n;
  return switch (link) {
    FoodLink.alcoholThreeOrMore => l.foodLinkAlcoholThreeOrMore,
    FoodLink.alcoholOneToTwo => l.foodLinkAlcoholOneToTwo,
    FoodLink.lateLastMeal => l.foodLinkLateLastMeal,
    FoodLink.caffeineAfter14 => l.foodLinkCaffeineAfter14(
      _clockOfMinute(f, caffeineLateMinute),
    ),
    FoodLink.heavyDinner => l.foodLinkHeavyDinner,
  };
}

String foodOutcomeLabel(AppLocalizations l, NightOutcome outcome) =>
    l.foodOutcomeName(outcome.name);

String foodFormatMagnitude(
  MetricFormat f,
  NightOutcome outcome,
  double absValue,
) {
  final l = f.l10n;
  final small = absValue > 0 && absValue < 1;
  final text = small ? f.decimal(absValue, digits: 1) : f.integer(absValue);
  return switch (outcome) {
    NightOutcome.heartRate => l.metricBpm(text),
    NightOutcome.hrv => l.metricPercent(text),
    NightOutcome.onset =>
      small
          ? l.metricDurationMinutes(0).replaceFirst('0', text)
          : f.duration(Duration(minutes: absValue.round())),
  };
}

String foodCompDeltaText(MetricFormat f, NightOutcome outcome, double value) {
  final direction = switch ((outcome, value >= 0)) {
    (NightOutcome.onset, true) => 'later',
    (NightOutcome.onset, false) => 'earlier',
    (_, true) => 'higher',
    (_, false) => 'lower',
  };
  return f.l10n.foodCompDelta(
    direction,
    foodFormatMagnitude(f, outcome, value.abs()),
  );
}

String foodPatternRangeText(
  MetricFormat f,
  NightOutcome outcome,
  double low,
  double high,
) {
  final a = low.abs();
  final b = high.abs();
  final small = a <= b ? a : b;
  final large = a <= b ? b : a;
  return f.l10n.metricTimeRange(
    foodFormatMagnitude(f, outcome, small),
    foodFormatMagnitude(f, outcome, large),
  );
}

String foodCompTagText(AppLocalizations l, LinkComparison comp) =>
    switch (comp) {
      LinkPattern() => l.foodCompTag('pattern'),
      LinkNoClearDifference() => l.foodCompTag('none'),
      LinkCollecting() => l.foodCompTag('collecting'),
    };

String foodLeadSummaryText(
  MetricFormat f,
  NightOutcome outcome,
  LinkComparison comp,
) {
  final l = f.l10n;
  return switch (comp) {
    final LinkCollecting c => l.foodCompCollecting(c.pairs, c.minimum),
    final LinkNoClearDifference d => l.foodCompNoClear(d.pairs),
    final LinkPattern p => l.foodCompPatternLine(
      p.pairs,
      foodOutcomeLabel(l, outcome),
      foodCompDeltaText(f, outcome, p.mean),
      foodPatternRangeText(f, outcome, p.low, p.high),
    ),
  };
}

class FoodComparisonsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = MetricFormat.of(context);
    if (!ref.watch(foodEnabledProvider)) {
      return AppPage(title: f.l10n.foodTitle, children: const []);
    }
    final state = ref.watch(foodComparisonsProvider);
    final t = Theme.of(context).textTheme;
    final c = AppColors.of(context);
    return AppPage(
      title: f.l10n.foodTitle,
      children: [
        const FoodSectionTabs(current: FoodSection.comparisons),
        const SizedBox(height: cardGap),
        ..._body(state, f, t, c),
      ],
    );
  }

  List<Widget> _body(
    AsyncValue<FoodComparisonsView> state,
    MetricFormat f,
    TextTheme t,
    AppColors c,
  ) {
    final l = f.l10n;
    if (state.hasError) return [BodyText(l.metricLoadError)];
    if (!state.hasValue) return const [SizedBox(height: 96)];
    final view = state.requireValue;
    return [
      BodyText(
        l.foodCompLead(foodCompareNights, f.date(view.updatedMonday)),
        key: FoodComparisonsKeys.lead,
      ),
      const SizedBox(height: cardGap),
      for (final item in view.items) ...[
        _comparisonCard(item, f, t, c),
        const SizedBox(height: cardGap),
      ],
      _regularityCard(view.regularity, f, t, c),
      const SizedBox(height: cardGap),
      CaptionText(l.foodCompFoot, key: FoodComparisonsKeys.foot),
      const SizedBox(height: 8),
      const FoodFormulaLink(buttonKey: FoodComparisonsKeys.formulaLink),
    ];
  }
}

Widget _comparisonCard(
  FoodComparisonItem item,
  MetricFormat f,
  TextTheme t,
  AppColors c,
) {
  final lead = item.lead;
  return MetricCard(
    key: FoodComparisonsKeys.card(item.link),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardHeader(
          foodLinkTitle(f, item.link),
          foodCompTagText(f.l10n, lead),
          t,
          c,
          tagKey: FoodComparisonsKeys.tag(item.link),
        ),
        const SizedBox(height: 10),
        BodyText(foodLeadSummaryText(f, item.leadOutcome, lead)),
        if (lead is LinkCollecting) ...[
          const SizedBox(height: 10),
          _collectingBar(
            lead.pairs,
            lead.minimum,
            c,
            key: FoodComparisonsKeys.progress(item.link),
          ),
        ],
      ],
    ),
  );
}

Widget _regularityCard(
  RegularityResult reg,
  MetricFormat f,
  TextTheme t,
  AppColors c,
) {
  final l = f.l10n;
  return MetricCard(
    key: FoodComparisonsKeys.regularityCard,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardHeader(l.foodRegTitle, l.foodRegTag, t, c),
        const SizedBox(height: 10),
        ..._regularityBody(reg, f),
      ],
    ),
  );
}

List<Widget> _regularityBody(RegularityResult reg, MetricFormat f) {
  final l = f.l10n;
  if (reg is RegularityCollecting) {
    return [BodyText(l.foodRegCollecting(reg.completeDays, reg.minimum))];
  }
  final r = reg as MealRegularity;
  final sd = f.duration(Duration(minutes: r.firstMealSdMinutes.round()));
  final summary = l.foodRegSummary(sd, r.completeDays);
  final shiftMin = r.weekendLaterMinutes?.round();
  final shiftText = _weekendShiftText(f, shiftMin);
  return [
    BodyText(shiftText == null ? summary : '$summary $shiftText'),
    const SizedBox(height: 8),
    CaptionText(l.foodRegNote),
  ];
}

String? _weekendShiftText(MetricFormat f, int? shiftMin) {
  if (shiftMin == null || shiftMin == 0) return null;
  final direction = shiftMin > 0 ? 'later' : 'earlier';
  return f.l10n.foodRegWeekend(
    direction,
    f.duration(Duration(minutes: shiftMin.abs())),
  );
}

Widget _cardHeader(
  String title,
  String tag,
  TextTheme t,
  AppColors c, {
  Key? tagKey,
}) => Wrap(
  alignment: WrapAlignment.spaceBetween,
  crossAxisAlignment: WrapCrossAlignment.center,
  spacing: 8,
  runSpacing: 4,
  children: [
    AccentTitle(title: title, accent: c.activity),
    DecoratedBox(
      key: tagKey,
      decoration: BoxDecoration(
        color: c.surfaceInner,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(tag, style: t.labelSmall?.copyWith(color: c.textSecondary)),
      ),
    ),
  ],
);

Widget _collectingBar(
  int pairs,
  int minimum,
  AppColors c, {
  required Key key,
}) => ExcludeSemantics(
  child: Row(
    key: key,
    children: [
      for (var i = 0; i < minimum; i++) ...[
        if (i > 0) const SizedBox(width: 3),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: i < pairs ? c.activity : c.surfaceBorder,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
            child: const SizedBox(height: 4),
          ),
        ),
      ],
    ],
  ),
);
