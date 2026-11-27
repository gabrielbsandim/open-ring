import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/energy/presentation/energy_evidence_sheet.dart';
import 'package:open_ring/features/food/application/food_week.dart';

enum FoodWeekEvidence { window, gap }

abstract final class FoodWeekEvidenceKeys {
  static const sheet = Key('food_week_evidence');
  static const kind = Key('food_week_evidence_kind');
  static const title = Key('food_week_evidence_title');
  static const value = Key('food_week_evidence_value');
  static const yours = Key('food_week_evidence_yours');
  static const rule = Key('food_week_evidence_rule');
  static const ours = Key('food_week_evidence_ours');
  static const limits = Key('food_week_evidence_limits');
  static const close = Key('food_week_evidence_close');
}

String foodWeekEvidenceYours(
  MetricFormat format,
  List<double> sortedMinutes,
  double medianMinutes,
) {
  final values = [
    for (final m in sortedMinutes)
      format.duration(Duration(minutes: m.round())),
  ].join(', ');
  final median = format.duration(Duration(minutes: medianMinutes.round()));
  return format.l10n.foodSheetDaysYours(sortedMinutes.length, values, median);
}

List<double> _values(FoodWeekView view, FoodWeekEvidence kind) =>
    kind == FoodWeekEvidence.window ? view.completeWindows : view.completeGaps;

double? _median(FoodWeekView view, FoodWeekEvidence kind) =>
    kind == FoodWeekEvidence.window
    ? view.stats.windowMinutes
    : view.stats.gapMinutes;

Future<void> showFoodWeekEvidence(
  BuildContext context, {
  required FoodWeekEvidence kind,
  required FoodWeekView view,
}) {
  if (_median(view, kind) == null || _values(view, kind).isEmpty) {
    return Future<void>.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.of(context).surface,
    builder: (context) => SafeArea(
      child: FoodWeekEvidenceSheet(kind: kind, view: view),
    ),
  );
}

class FoodWeekEvidenceSheet extends StatelessWidget {
  const new({required this.kind, required this.view, super.key});

  final FoodWeekEvidence kind;
  final FoodWeekView view;

  @override
  Widget build(BuildContext context) {
    final f = MetricFormat.of(context);
    final l = f.l10n;
    final t = Theme.of(context).textTheme;
    final win = kind == FoodWeekEvidence.window;
    final median = _median(view, kind) ?? 0;
    final values = _values(view, kind);
    final sections = [
      (
        null,
        l.overallSheetWhat,
        win ? l.foodSheetWindowWhat : l.foodSheetGapWhat,
      ),
      (
        FoodWeekEvidenceKeys.yours,
        l.overallSheetYours,
        foodWeekEvidenceYours(f, values, median),
      ),
      (
        FoodWeekEvidenceKeys.rule,
        l.overallSheetRule,
        '${win ? l.foodSheetWindowRule : l.foodSheetGapRule}\n\n${l.foodSheetMedianMath}',
      ),
      (
        FoodWeekEvidenceKeys.ours,
        l.overallSheetOurs,
        win ? l.foodSheetWindowOurs : l.foodSheetGapOurs,
      ),
      (
        FoodWeekEvidenceKeys.limits,
        l.overallSheetLimits,
        win ? l.foodSheetWindowLimits : l.foodSheetGapLimits,
      ),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        key: FoodWeekEvidenceKeys.sheet,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CaptionText(l.foodSheetKind, key: FoodWeekEvidenceKeys.kind),
            const SizedBox(height: 4),
            Semantics(
              header: true,
              child: Text(
                win ? l.foodWindowTitle : l.foodWeekGapTitle,
                key: FoodWeekEvidenceKeys.title,
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 12,
              runSpacing: 4,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      f.duration(Duration(minutes: median.round())),
                      key: FoodWeekEvidenceKeys.value,
                      style: numberStyle(t.headlineSmall),
                    ),
                    CaptionText(l.foodSheetUnitMedian),
                  ],
                ),
                CaptionText(
                  l.metricTimeRange(
                    f.monthDay(view.monday),
                    f.monthDay(view.sunday),
                  ),
                ),
              ],
            ),
            for (final s in sections)
              EnergyEvidenceSection(key: s.$1, title: s.$2, body: s.$3),
            const SizedBox(height: 16),
            OutlinedButton(
              key: FoodWeekEvidenceKeys.close,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.foodMealClose),
            ),
          ],
        ),
      ),
    );
  }
}
