import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/trajectory/application/trajectory_kcal_providers.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_evidence_sheet.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_more_evidence.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class TrajectoryKcalCard extends ConsumerWidget {
  const new({required this.format, super.key});

  final MetricFormat format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kcal = ref.watch(trajectoryKcalProvider).value;
    if (kcal is! KcalReady) return const SizedBox.shrink();
    final units = UnitFormat.of(context, ref);
    final view = ref.watch(trajectoryViewProvider).value;
    final scenarioKg = view is TrajectoryReady
        ? view.band.mid - view.trendKg
        : 0.0;
    void open(KcalEvidence kind) => unawaited(
      showGoalEvidence(
        context,
        copy: kcalEvidenceCopy(format, kind),
        yours: kcalEvidenceYours(units, kind, kcal, scenarioKg: scenarioKg),
      ),
    );
    final l10n = format.l10n;
    String range(int low, int high) =>
        l10n.trajectoryKcalRange(format.integer(low), format.integer(high));
    final resting = kcal.resting;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: MetricCard(
        key: TrajectoryKeys.kcal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.trajectoryKcalTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            CaptionText(l10n.trajectoryKcalFrom),
            if (resting != null)
              _Row(
                caption: l10n.trajectoryKcalResting,
                value: range(resting.low, resting.high),
                why: l10n.trajectoryKcalRestingWhy,
                onTap: () => open(KcalEvidence.resting),
              ),
            if (kcal case KcalReady(
              :final int restChange12,
              :final int dayChange12,
            ))
              _change(l10n, restChange12, dayChange12, open),
            _balance(l10n, kcal.balance, range, open),
            const SizedBox(height: 12),
            CaptionText(l10n.trajectoryKcalCaption),
          ],
        ),
      ),
    );
  }

  Widget _change(
    AppLocalizations l10n,
    int rest,
    int day,
    void Function(KcalEvidence) open,
  ) {
    if (rest == 0) {
      return _Row(
        caption: l10n.trajectoryKcalScenario,
        value: l10n.trajectoryKcalSame,
        why: l10n.trajectoryKcalSameWhy,
        onTap: () => open(KcalEvidence.scenario),
      );
    }
    final whole = format.integer(day.abs());
    return _Row(
      caption: l10n.trajectoryKcalScenario,
      value: l10n.trajectoryKcalAbout(format.integer(rest.abs())),
      why: rest < 0
          ? l10n.trajectoryKcalLessWhy(whole)
          : l10n.trajectoryKcalMoreWhy(whole),
      onTap: () => open(KcalEvidence.scenario),
    );
  }

  Widget _balance(
    AppLocalizations l10n,
    EnergyBalance balance,
    String Function(int low, int high) range,
    void Function(KcalEvidence) open,
  ) {
    final (value, why) = switch (balance) {
      EnergyBalanceNoRate() => (
        l10n.trajectoryKcalNotYet,
        l10n.trajectoryKcalNoRateWhy,
      ),
      EnergyBalanceCount(:final weighIns) => (
        l10n.trajectoryKcalNotYet,
        l10n.trajectoryKcalCountWhy(
          format.integer(foodEnergyMinWeighIns),
          format.integer(weighIns),
        ),
      ),
      EnergyBalanceBlock(:final from) => (
        l10n.trajectoryKcalFromDate(format.monthDay(from)),
        l10n.trajectoryKcalBlockWhy,
      ),
      EnergyBalanceReady(balanced: true) => (
        l10n.trajectoryKcalBalanced,
        l10n.trajectoryKcalBalancedWhy,
      ),
      // The side comes from the raw ends; a stepped end can round to zero.
      EnergyBalanceReady(:final shown, :final high) when high < 0 => (
        range(-shown.high, -shown.low),
        l10n.trajectoryKcalBelowWhy,
      ),
      EnergyBalanceReady(:final shown) => (
        range(shown.low, shown.high),
        l10n.trajectoryKcalAboveWhy,
      ),
    };
    return _Row(
      caption: l10n.trajectoryKcalBalance,
      value: value,
      why: why,
      onTap: () => open(KcalEvidence.balance),
    );
  }
}

class _Row extends StatelessWidget {
  const new({
    required this.caption,
    required this.value,
    required this.why,
    required this.onTap,
  });

  final String caption;
  final String value;
  final String why;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: EvidenceTap(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptionText(caption),
            const SizedBox(height: 2),
            Text(
              value,
              style: numberStyle(Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 4),
            CaptionText(why),
          ],
        ),
      ),
    );
  }
}
