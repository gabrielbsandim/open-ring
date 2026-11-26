import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/presentation/hidden_numbers.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_chart.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_evidence_sheet.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_kcal_card.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_states.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class TrajectoryKeys {
  static const card = Key('trajectory_card');
  static const chart = Key('trajectory_chart');
  static const now = Key('trajectory_now');
  static const firm = Key('trajectory_firm');
  static const band = Key('trajectory_band');
  static const rate = Key('trajectory_rate');
  static const placeholder = Key('trajectory_placeholder');
  static const building = Key('trajectory_building');
  static const none = Key('trajectory_none');
  static const guard = Key('trajectory_guard');
  static const refused = Key('trajectory_refused');
  static const error = Key('trajectory_error');
  static const retry = Key('trajectory_retry');
  static const hidden = Key('trajectory_hidden');
  static const direction = Key('trajectory_direction');
  static const kcal = Key('trajectory_kcal');
  static const whatIfLink = Key('trajectory_what_if_link');
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
        ..._content(ref, units, view, summary, hidden: hidden),
      ],
    );
  }

  List<Widget> _content(
    WidgetRef ref,
    UnitFormat units,
    AsyncValue<TrajectoryView> view,
    AsyncValue<WeightSummary?> summary, {
    required bool hidden,
  }) {
    final error = TrajectoryErrorCard(
      onRetry: () {
        ref
          ..invalidate(weighInsProvider)
          ..invalidate(weightSummaryProvider)
          ..invalidate(trajectoryViewProvider);
      },
    );
    if (view.hasError || summary.hasError) return [error];
    if (!view.hasValue || !summary.hasValue) return const [];
    final weights = summary.value;
    return switch (view.requireValue) {
      TrajectoryError() => [error],
      TrajectoryOff() => [
        BodyText(
          key: TrajectoryKeys.placeholder,
          units.l10n.trajectoryPlaceholder,
        ),
      ],
      TrajectoryRefused(:final reason) => [
        TrajectoryRefusedCard(reason: reason),
      ],
      TrajectoryGuard(:final loss) => [
        TrajectoryGuardCard(
          loss: loss,
          summary: weights,
          units: units,
          hidden: hidden,
        ),
        const _WhatIfLink(),
      ],
      TrajectoryBuilding() || TrajectoryReady() when weights == null => [
        const TrajectoryNone(),
        const _WhatIfLink(),
      ],
      TrajectoryBuilding(:final rate) => [
        TrajectoryBuildingCard(
          rate: rate,
          summary: weights!,
          units: units,
          hidden: hidden,
        ),
        const _WhatIfLink(),
      ],
      final TrajectoryReady ready => [
        if (hidden) ...[
          HiddenNumbersLabel(
            key: TrajectoryKeys.hidden,
            units.l10n.trajectoryHiddenNote,
          ),
          const SizedBox(height: 12),
        ],
        _ScenarioCard(
          view: ready,
          summary: weights!,
          units: units,
          hidden: hidden,
        ),
        TrajectoryKcalCard(format: units.format),
        const _WhatIfLink(),
      ],
    };
  }
}

class _ScenarioCard extends StatelessWidget {
  const new({
    required this.view,
    required this.summary,
    required this.units,
    required this.hidden,
  });

  final TrajectoryReady view;
  final WeightSummary summary;
  final UnitFormat units;
  final bool hidden;

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
    void open(TrajectoryEvidence kind) => unawaited(
      showGoalEvidence(
        context,
        copy: trajectoryEvidenceCopy(units, kind),
        yours: trajectoryEvidenceYours(units, kind, view),
      ),
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
          if (!hidden) ...[
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _Tile(
                  key: TrajectoryKeys.now,
                  caption: l10n.trajectoryNow(units.format.monthDay(view.asOf)),
                  value: units.bodyWeight(view.trendKg),
                  onTap: () => open(TrajectoryEvidence.rate),
                ),
                _Tile(
                  key: TrajectoryKeys.firm,
                  caption: weeks(view.firm),
                  value: range(view.firm),
                  onTap: () => open(TrajectoryEvidence.firm),
                ),
                _Tile(
                  key: TrajectoryKeys.band,
                  caption: weeks(view.band),
                  value: range(view.band),
                  onTap: () => open(TrajectoryEvidence.band),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          TrajectoryChart(
            key: TrajectoryKeys.chart,
            view: view,
            daily: summary.daily,
            line: summary.line,
            units: units,
            hidden: hidden,
          ),
          if (!hidden) ...[
            const SizedBox(height: 8),
            CaptionText(l10n.trajectoryLegendBand),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: colors.surfaceBorder),
          const SizedBox(height: 14),
          if (hidden)
            _Direction(rate: view.rate, l10n: l10n)
          else
            _Rate(
              rate: view.rate,
              units: units,
              onTap: () => open(TrajectoryEvidence.rate),
            ),
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
  const new({
    required this.caption,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String caption;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
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

class _Tappable extends StatelessWidget {
  const new({required this.onTap, required this.child, super.key});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: child,
        ),
      ),
    );
  }
}

class _Rate extends StatelessWidget {
  const new({required this.rate, required this.units, required this.onTap});

  final WeightRateReady rate;
  final UnitFormat units;
  final VoidCallback onTap;

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
    return _Tappable(
      key: TrajectoryKeys.rate,
      onTap: onTap,
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

class _Direction extends StatelessWidget {
  const new({required this.rate, required this.l10n});

  final WeightRateReady rate;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      key: TrajectoryKeys.direction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CaptionText(l10n.bodyDirectionTitle),
          const SizedBox(height: 2),
          Text(
            weightDirection(l10n, rate),
            style: numberStyle(Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 4),
          CaptionText(
            rate.stable
                ? l10n.bodyDirectionStableWhy
                : l10n.bodyDirectionMovingWhy,
          ),
        ],
      ),
    );
  }
}

class _WhatIfLink extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: MetricCard(
        key: TrajectoryKeys.whatIfLink,
        onTap: () => unawaited(context.push(AppPaths.trajectoryWhatIf)),
        child: MergeSemantics(
          child: Semantics(
            button: true,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.trajectoryWhatIfTitle,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      CaptionText(l10n.trajectoryWhatIfLinkBody),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: colors.textLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
