import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_chart.dart';

abstract final class TrajectoryKeys {
  static const card = Key('trajectory_card');
  static const chart = Key('trajectory_chart');
  static const now = Key('trajectory_now');
  static const firm = Key('trajectory_firm');
  static const band = Key('trajectory_band');
  static const rate = Key('trajectory_rate');
  static const placeholder = Key('trajectory_placeholder');
}

class TrajectoryScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = UnitFormat.of(context, ref);
    final l10n = units.l10n;
    final view = ref.watch(trajectoryViewProvider);
    final summary = ref.watch(weightSummaryProvider);
    final hidden = ref.watch(numbersHiddenProvider);
    return AppPage(
      title: l10n.trajectoryTitle,
      children: [
        CaptionText(l10n.trajectoryLead),
        const SizedBox(height: 16),
        ...switch ((view, summary)) {
          (AsyncError(), _) || (_, AsyncError()) => [
            BodyText(key: TrajectoryKeys.placeholder, l10n.metricLoadError),
          ],
          (AsyncData(value: TrajectoryError()), _) => [
            BodyText(key: TrajectoryKeys.placeholder, l10n.metricLoadError),
          ],
          (
            AsyncData(value: final TrajectoryReady ready),
            AsyncData(value: final WeightSummary weights),
          )
              when !hidden =>
            [_ScenarioCard(view: ready, summary: weights, units: units)],
          (AsyncData(), AsyncData()) => [
            BodyText(
              key: TrajectoryKeys.placeholder,
              l10n.trajectoryPlaceholder,
            ),
          ],
          _ => const <Widget>[],
        },
      ],
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const new({required this.view, required this.summary, required this.units});

  final TrajectoryReady view;
  final WeightSummary summary;
  final UnitFormat units;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = units.l10n;
    final theme = Theme.of(context);
    String range(ScenarioBand band) => l10n.trajectoryRange(
      units.bodyWeightNumber(band.low),
      units.bodyWeightNumber(band.high),
      units.weightUnit,
    );
    String weeks(ScenarioBand band) => l10n.trajectoryWeeksAt(
      band.days ~/ 7,
      units.format.monthDay(view.asOf.addDays(band.days)),
    );
    return MetricCard(
      key: TrajectoryKeys.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.trajectoryCardTitle,
              style: theme.textTheme.titleMedium,
            ),
          ),
          CaptionText(l10n.trajectoryCardSubtitle),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _Tile(
                key: TrajectoryKeys.now,
                caption: l10n.trajectoryNow(units.format.monthDay(view.asOf)),
                value: units.bodyWeight(view.trendKg),
              ),
              _Tile(
                key: TrajectoryKeys.firm,
                caption: weeks(view.firm),
                value: range(view.firm),
              ),
              _Tile(
                key: TrajectoryKeys.band,
                caption: weeks(view.band),
                value: range(view.band),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TrajectoryChart(
            key: TrajectoryKeys.chart,
            view: view,
            daily: summary.daily,
            line: summary.line,
            units: units,
          ),
          const SizedBox(height: 8),
          CaptionText(l10n.trajectoryLegendBand),
          const SizedBox(height: 14),
          Divider(height: 1, color: colors.surfaceBorder),
          const SizedBox(height: 14),
          _Rate(rate: view.rate, units: units),
          const SizedBox(height: 10),
          CaptionText(
            [
              l10n.trajectoryAssumption,
              if (view.rate.stable) l10n.trajectoryStableNote,
              if (!view.rate.stable && view.rate.perWeek < 0)
                l10n.trajectoryBendNote,
              l10n.trajectoryNotForecast,
            ].join(' '),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const new({required this.caption, required this.value, super.key});

  final String caption;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CaptionText(caption),
          Text(
            value,
            style: numberStyle(Theme.of(context).textTheme.titleSmall),
          ),
        ],
      ),
    );
  }
}

class _Rate extends StatelessWidget {
  const new({required this.rate, required this.units});

  final WeightRateReady rate;
  final UnitFormat units;

  @override
  Widget build(BuildContext context) {
    final l10n = units.l10n;
    final unit = units.weightUnit;
    String perWeek(double kilograms) =>
        units.format.signed(units.bodyWeightIn(kilograms), digits: 2);
    final low = perWeek(rate.low);
    final high = perWeek(rate.high);
    final (value, why) = rate.stable
        ? (l10n.bodyRateStableTitle, l10n.bodyRateStableWhy(low, high, unit))
        : (
            l10n.bodyWeightRatePerWeek(perWeek(rate.perWeek), unit),
            l10n.bodyRateInterval(low, high, unit),
          );
    return MergeSemantics(
      key: TrajectoryKeys.rate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CaptionText(l10n.bodyWeightRate),
          const SizedBox(height: 2),
          Text(
            value,
            style: numberStyle(Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 4),
          CaptionText(why),
        ],
      ),
    );
  }
}
