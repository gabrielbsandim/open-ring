import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';

abstract final class FoodEnergyViewKeys {
  static const rangeCard = Key('food_energy_range_card');
  static const range = Key('food_energy_range');
  static const bar = Key('food_energy_bar');
  static const ring = Key('food_energy_ring');
  static const rangeNote = Key('food_energy_range_note');
  static const gapCard = Key('food_energy_gap_card');
  static const gap = Key('food_energy_gap');
  static const change = Key('food_energy_change');
  static const changeNote = Key('food_energy_change_note');
  static const mathCard = Key('food_energy_math_card');
  static const mathWeight = Key('food_energy_math_weight');
  static const math = Key('food_energy_math');
  static const limits = Key('food_energy_limits');
  static const holdCard = Key('food_energy_hold_card');
  static const hold = Key('food_energy_hold');
  static const lastRange = Key('food_energy_last_range');
  static const sample = Key('food_energy_sample');
}

/// The demo sample: the F1 inputs over the week of 2026-11-30 to 2026-12-06.
final foodEnergySample = FoodEnergyReady(
  const FoodEnergyCounts(
    sunday: LocalDate(2026, 12, 6),
    days: 30,
    weekDays: 6,
    weighIns: 28,
    ringDays: 35,
  ),
  foodEnergyFigures(
    slopeKgPerDay: -0.03,
    logMean: 1780,
    weekMean: 1700,
    previousMean: 1800,
    ringMean: 2500,
  ),
);

const _barFloor = 0.5;
const _barCeiling = 1.3;

/// Where the band and the ring mean fall on a bar from 50 to 130 percent of
/// the ring mean, each as a fraction of the bar clamped to it.
({double low, double high, double ring}) foodEnergyBarSpan(
  FoodEnergyFigures x,
) {
  double at(num kcal) =>
      ((kcal / x.ringMean - _barFloor) / (_barCeiling - _barFloor)).clamp(0, 1);
  return (low: at(x.weekLow), high: at(x.weekHigh), ring: at(x.ringMean));
}

String foodEnergyRangeText(MetricFormat f, FoodEnergyFigures x) =>
    f.l10n.foodEnergyRange(f.integer(x.weekLow), f.integer(x.weekHigh));

String foodEnergyGapText(MetricFormat f, FoodEnergyFigures x) {
  final shown = x.gapShown;
  return f.l10n.foodEnergyGap(
    x.gapDirection.name,
    f.integer(shown?.low ?? 0),
    f.integer(shown?.high ?? 0),
  );
}

String foodEnergyWeekDates(MetricFormat f, LocalDate sunday) =>
    f.l10n.metricTimeRange(f.monthDay(sunday.addDays(-6)), f.monthDay(sunday));

/// A card title on the left and a state tag on the right, wrapping at large
/// text; shared by the Week screen cards and the Weekly energy cards.
Widget cardHeader(Widget title, String tag, {Widget? trailing}) => Wrap(
  alignment: WrapAlignment.spaceBetween,
  crossAxisAlignment: WrapCrossAlignment.center,
  spacing: 8,
  runSpacing: 4,
  children: [
    title,
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: CaptionText(tag)),
        ?trailing,
      ],
    ),
  ],
);

Widget _card(Key key, List<Widget> children) => MetricCard(
  key: key,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  ),
);

Widget _expr(BuildContext context, String text, {Key? key}) {
  final c = AppColors.of(context);
  return DecoratedBox(
    key: key,
    decoration: BoxDecoration(
      color: c.surfaceInner,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: numberStyle(Theme.of(context).textTheme.bodySmall),
      ),
    ),
  );
}

/// The range card, the gap and change card, the arithmetic and the limits.
class FoodEnergyReadyView extends ConsumerWidget {
  const new(this.ready, {super.key});

  final FoodEnergyReady ready;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = MetricFormat.of(context);
    final l = f.l10n;
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final x = ready.figures;
    final counts = ready.counts;
    final change = x.changeShown;
    final perKg = f.integer(foodEnergyKcalPerKg);
    final weightHidden = ref.watch(profileWeightHiddenProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(FoodEnergyViewKeys.rangeCard, [
          cardHeader(
            AccentTitle(
              title: foodEnergyWeekDates(f, counts.sunday),
              accent: c.activity,
            ),
            l.foodEnergyTag('range'),
          ),
          const SizedBox(height: 10),
          Text(
            foodEnergyRangeText(f, x),
            key: FoodEnergyViewKeys.range,
            style: numberStyle(t.titleLarge),
          ),
          const SizedBox(height: 12),
          _RangeBar(x),
          const SizedBox(height: 6),
          CaptionText(
            l.foodEnergyRing(f.integer(x.ringMean)),
            key: FoodEnergyViewKeys.ring,
          ),
          const SizedBox(height: 10),
          BodyText(
            l.foodEnergyRangeNote(counts.weekDays),
            key: FoodEnergyViewKeys.rangeNote,
          ),
        ]),
        const SizedBox(height: cardGap),
        _card(FoodEnergyViewKeys.gapCard, [
          AccentTitle(title: l.foodEnergyGapTitle, accent: c.textPrimary),
          const SizedBox(height: 6),
          Text(
            foodEnergyGapText(f, x),
            key: FoodEnergyViewKeys.gap,
            style: numberStyle(t.titleMedium),
          ),
          const SizedBox(height: 6),
          CaptionText(l.foodEnergyGapNote),
          const SizedBox(height: 16),
          AccentTitle(title: l.foodEnergyChangeTitle, accent: c.textPrimary),
          const SizedBox(height: 6),
          Text(
            l.foodEnergyChange(x.changeDirection.name),
            key: FoodEnergyViewKeys.change,
            style: numberStyle(t.titleMedium),
          ),
          const SizedBox(height: 6),
          CaptionText(
            l.foodEnergyChangeNote(
              f.integer(change.low),
              f.integer(change.high),
            ),
            key: FoodEnergyViewKeys.changeNote,
          ),
        ]),
        const SizedBox(height: cardGap),
        _card(FoodEnergyViewKeys.mathCard, [
          AccentTitle(title: l.overallSheetRule, accent: c.textPrimary),
          const SizedBox(height: 10),
          if (!weightHidden) ...[
            _expr(
              context,
              l.foodEnergyMathWeight(
                f.decimal(x.slopeKgPerDay, digits: 3),
                perKg,
                f.integer(x.balance),
              ),
              key: FoodEnergyViewKeys.mathWeight,
            ),
            const SizedBox(height: 8),
          ],
          _expr(
            context,
            l.foodEnergyMath(
              f.monthDay(counts.sunday.addDays(1 - foodEnergyWindowDays)),
              f.monthDay(counts.sunday),
              counts.weighIns,
              counts.days,
              f.integer(x.logMean),
              f.integer(x.expenditureLog),
              f.integer(x.ringMean),
              f.decimal(x.factorLow, digits: 2),
              f.decimal(x.factorHigh, digits: 2),
              f.integer(x.weekMean),
              f.integer(x.weekLow),
              f.integer(x.weekHigh),
            ),
            key: FoodEnergyViewKeys.math,
          ),
          const SizedBox(height: 10),
          CaptionText(l.foodEnergyMathNote(perKg)),
        ]),
        const SizedBox(height: cardGap),
        _card(FoodEnergyViewKeys.limits, [
          AccentTitle(title: l.overallSheetLimits, accent: c.textPrimary),
          const SizedBox(height: 8),
          BodyText(l.foodEnergyLimits),
        ]),
      ],
    );
  }
}

/// No new range this week, with the last ready range muted below.
class FoodEnergyHoldView extends StatelessWidget {
  const new(this.hold, {super.key});

  final FoodEnergyHold hold;

  @override
  Widget build(BuildContext context) {
    final f = MetricFormat.of(context);
    final l = f.l10n;
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final last = hold.last;
    return _card(FoodEnergyViewKeys.holdCard, [
      cardHeader(
        AccentTitle(title: l.foodEnergyHoldTitle, accent: c.activity),
        l.foodEnergyTag('holding'),
      ),
      const SizedBox(height: 8),
      BodyText(
        l.foodEnergyHold(hold.reason.name),
        key: FoodEnergyViewKeys.hold,
      ),
      if (last != null) ...[
        const SizedBox(height: 12),
        DecoratedBox(
          key: FoodEnergyViewKeys.lastRange,
          decoration: BoxDecoration(
            color: c.surfaceInner,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CaptionText(
                  l.foodEnergyLastRange(
                    foodEnergyWeekDates(f, last.counts.sunday),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  foodEnergyRangeText(f, last.figures),
                  style: numberStyle(t.titleMedium, color: c.textLabel),
                ),
              ],
            ),
          ),
        ),
      ],
    ]);
  }
}

class _RangeBar extends StatelessWidget {
  const new(this.figures);

  final FoodEnergyFigures figures;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      key: FoodEnergyViewKeys.bar,
      height: 16,
      width: double.infinity,
      child: CustomPaint(
        painter: _RangeBarPainter(
          foodEnergyBarSpan(figures),
          AppColors.of(context),
        ),
      ),
    ),
  );
}

class _RangeBarPainter extends CustomPainter {
  new(this.span, this.colors);

  final ({double low, double high, double ring}) span;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final w = size.width;
    canvas
      ..drawRRect(
        RRect.fromLTRBR(0, mid - 3, w, mid + 3, const Radius.circular(3)),
        Paint()..color = colors.track,
      )
      ..drawRRect(
        RRect.fromLTRBR(
          span.low * w,
          mid - 5,
          span.high * w,
          mid + 5,
          const Radius.circular(5),
        ),
        Paint()..color = colors.activity,
      )
      ..drawRect(
        Rect.fromLTWH(span.ring * w - 1, 0, 2, size.height),
        Paint()..color = colors.textPrimary,
      );
  }

  @override
  bool shouldRepaint(_RangeBarPainter old) =>
      old.span != span || old.colors != colors;
}
