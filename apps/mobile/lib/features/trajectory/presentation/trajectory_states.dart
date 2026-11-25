import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/presentation/weigh_in_sheet.dart';
import 'package:open_ring/features/body/presentation/weight_chart.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class TrajectoryNone extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyStateCard(
      key: TrajectoryKeys.none,
      icon: Icons.monitor_weight_outlined,
      accent: AppColors.of(context).textLabel,
      title: l10n.bodyEmptyTitle,
      message: l10n.trajectoryNoneText,
      actionLabel: l10n.bodyWeightLogFirst,
      onAction: () => unawaited(showWeighInSheet(context)),
    );
  }
}

class TrajectoryBuildingCard extends StatelessWidget {
  const new({
    required this.rate,
    required this.summary,
    required this.units,
    required this.hidden,
    super.key,
  });

  final WeightRateBuilding? rate;
  final WeightSummary summary;
  final UnitFormat units;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final l10n = units.l10n;
    final days = summary.daily;
    final missing = rate;
    return _StateCard(
      key: TrajectoryKeys.building,
      title: l10n.trajectoryBuildingTitle,
      children: [
        BodyText(
          [
            l10n.bodyRateNeeds(weightRateMinDays, weightRateMinSpanDays),
            if (missing != null && missing.daysMissing > 0)
              l10n.trajectoryMissingDays(missing.daysMissing),
            if (missing != null && missing.spanMissing > 0)
              l10n.trajectoryMissingSpan(missing.spanMissing),
          ].join(' '),
        ),
        const SizedBox(height: 6),
        CaptionText(
          l10n.trajectoryBuildingCount(
            days.length,
            units.format.monthDay(days.first.date),
            units.format.monthDay(days.last.date),
          ),
        ),
        const SizedBox(height: 14),
        _WeighInChart(summary: summary, units: units, hidden: hidden),
      ],
    );
  }
}

class TrajectoryGuardCard extends StatelessWidget {
  const new({
    required this.loss,
    required this.summary,
    required this.units,
    required this.hidden,
    super.key,
  });

  final LossRate loss;
  final WeightSummary? summary;
  final UnitFormat units;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final l10n = units.l10n;
    final weights = summary;
    final rate = hidden
        ? l10n.trajectoryGuardHidden
        : l10n.trajectoryGuardRate(
            units.format.decimal(loss.percentLow, digits: 2),
            units.format.decimal(loss.percentHigh, digits: 2),
          );
    return _StateCard(
      key: TrajectoryKeys.guard,
      title: l10n.trajectoryGuardTitle,
      children: [
        BodyText(rate),
        const SizedBox(height: 6),
        CaptionText(l10n.trajectoryGuardAdvice),
        if (weights != null) ...[
          const SizedBox(height: 14),
          _WeighInChart(summary: weights, units: units, hidden: hidden),
        ],
      ],
    );
  }
}

class TrajectoryRefusedCard extends StatelessWidget {
  const new({required this.reason, super.key});

  final TrajectoryRefusal reason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StateCard(
      key: TrajectoryKeys.refused,
      title: l10n.trajectoryRefusedTitle,
      children: [
        BodyText(switch (reason) {
          TrajectoryRefusal.underage => l10n.trajectoryRefusedUnderage,
          TrajectoryRefusal.pregnancy => l10n.trajectoryRefusedPregnancy,
          TrajectoryRefusal.noHeight => l10n.trajectoryRefusedNoHeight,
        }),
        if (reason == TrajectoryRefusal.noHeight) ...[
          const SizedBox(height: 14),
          ActionButton(
            label: l10n.energyOpenProfile,
            onPressed: () => context.go(AppPaths.settings),
          ),
        ],
      ],
    );
  }
}

class TrajectoryErrorCard extends StatelessWidget {
  const new({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MetricCard(
      key: TrajectoryKeys.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BodyText(l10n.metricLoadError),
          const SizedBox(height: 14),
          ActionButton(
            key: TrajectoryKeys.retry,
            label: l10n.trajectoryRetry,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const new({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _WeighInChart extends ConsumerWidget {
  const new({required this.summary, required this.units, required this.hidden});

  final WeightSummary summary;
  final UnitFormat units;
  final bool hidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WeightChart(
      daily: summary.daily,
      line: summary.line,
      today: ref.watch(currentDateProvider),
      range: WeightRange.month,
      units: units,
      band: hidden ? summary.noise : null,
    );
  }
}
