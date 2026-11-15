import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/presentation/weigh_in_sheet.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';

abstract final class WeightCardKeys {
  static const card = Key('today_weight');
  static const log = Key('today_weight_log');
}

class WeightCardSlot extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(
      enabledModulesProvider.select(
        (modules) => modules.value?.contains(ModuleId.body) ?? false,
      ),
    );
    if (!on) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(top: cardGap),
      child: WeightCard(),
    );
  }
}

class WeightCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = UnitFormat.of(context, ref);
    return MetricCard(
      key: WeightCardKeys.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: units.l10n.profileWeight,
            accent: AppColors.of(context).textLabel,
          ),
          const SizedBox(height: 8),
          _content(ref.watch(weightSummaryProvider), units),
        ],
      ),
    );
  }

  Widget _content(AsyncValue<WeightSummary?> summary, UnitFormat units) {
    if (summary.hasValue) return _WeightBody(summary: summary.value);
    if (summary.hasError) return BodyText(units.l10n.metricLoadError);
    return const SizedBox(height: 48);
  }
}

class _WeightBody extends ConsumerWidget {
  const new({required this.summary});

  final WeightSummary? summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final units = UnitFormat.of(context, ref);
    final l10n = units.l10n;
    final summary = this.summary;
    void log() => unawaited(showWeighInSheet(context));
    if (summary == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BodyText(l10n.bodyWeightEmpty),
          const SizedBox(height: 14),
          SecondaryButton(
            key: WeightCardKeys.log,
            label: l10n.bodyWeightLogFirst,
            onPressed: log,
          ),
        ],
      );
    }
    final last = summary.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 4,
                children: [
                  Text(
                    units.bodyWeightNumber(summary.trend),
                    style: numberStyle(theme.textTheme.headlineMedium),
                  ),
                  Text(
                    units.weightUnit,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textLabel,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              CaptionText(l10n.bodyWeightTrend),
            ],
          ),
        ),
        const SizedBox(height: 10),
        MetricRow(
          label: l10n.bodyWeightLast,
          value: l10n.bodyWeightLastOn(
            units.bodyWeight(last.kilograms),
            units.format.clockOrDay(last.at, ref.watch(clockProvider)()),
          ),
        ),
        const SizedBox(height: 6),
        MetricRow(
          label: l10n.bodyWeightRate,
          value: _rate(units, summary.rate),
        ),
        const SizedBox(height: 14),
        SecondaryButton(
          key: WeightCardKeys.log,
          label: l10n.bodyWeightLog,
          onPressed: log,
        ),
      ],
    );
  }

  String _rate(UnitFormat units, WeightRate rate) => switch (rate) {
    WeightRateBuilding() => units.l10n.bodyWeightRateBuilding,
    WeightRateReady(stable: true) => units.l10n.bodyWeightRateStable,
    WeightRateReady(:final perWeek) => units.l10n.bodyWeightRatePerWeek(
      units.format.signed(units.bodyWeightIn(perWeek), digits: 2),
      units.weightUnit,
    ),
  };
}
