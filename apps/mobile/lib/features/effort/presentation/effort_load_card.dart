import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/effort/presentation/effort_evidence_sheet.dart';

abstract final class EffortLoadKeys {
  static const card = Key('effort_load');
  static const building = Key('effort_load_building');
  static const buildingDays = Key('effort_load_building_days');
  static const chart = Key('effort_load_chart');
  static const acute = Key('effort_load_acute');
  static const chronic = Key('effort_load_chronic');
  static const noRatio = Key('effort_load_no_ratio');
  static const lines = Key('effort_load_lines');
}

/// The daily load, oldest first and ending yesterday, with its two lines as
/// two separate numbers.
class EffortLoadCard extends StatelessWidget {
  const new({required this.dailyLoad, super.key});

  final List<double> dailyLoad;

  @override
  Widget build(BuildContext context) {
    final l10n = MetricFormat.of(context).l10n;
    final theme = Theme.of(context).textTheme;
    final acute = loadLine(dailyLoad, days: effortAcuteDays);
    final chronic = loadLine(dailyLoad, days: effortChronicDays);
    return MetricCard(
      key: EffortLoadKeys.card,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.effortLoadTitle,
              style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          if (acute == null || chronic == null)
            _Building(days: dailyLoad.length)
          else
            _Lines(dailyLoad: dailyLoad, acute: acute, chronic: chronic),
        ],
      ),
    );
  }
}

class _Building extends StatelessWidget {
  const new({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    final target = format.integer(effortMinLoadDays);
    return Column(
      key: EffortLoadKeys.building,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.effortLoadBuildingTitle,
          style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.effortLoadBuildingDays(format.integer(days), target),
                key: EffortLoadKeys.buildingDays,
                style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ExcludeSemantics(
                child: ProgressBar(
                  value: (days / effortMinLoadDays).clamp(0, 1),
                  color: colors.textLabel,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.effortLoadBuildingBody(target),
          style: theme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 8),
        CaptionText(l10n.effortLoadBuildingNote),
      ],
    );
  }
}

class _Lines extends StatelessWidget {
  const new({
    required this.dailyLoad,
    required this.acute,
    required this.chronic,
  });

  final List<double> dailyLoad;
  final double acute;
  final double chronic;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    final shown = dailyLoad.sublist(
      math.max(0, dailyLoad.length - effortChronicDays),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.effortLoadLead,
          style: theme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 12),
        HourlyBars(
          key: EffortLoadKeys.chart,
          values: shown,
          color: colors.activity,
          semanticsLabel: l10n.effortLoadChartSemantics(
            format.integer(shown.length),
          ),
          height: 110,
        ),
        const SizedBox(height: 12),
        MergeSemantics(
          child: InkWell(
            key: EffortLoadKeys.lines,
            onTap: () => showEffortEvidence(
              context,
              kind: EffortEvidence.lines,
              yours: l10n.effortSheetLinesYours(
                format.integer(effortAcuteDays),
                format.integer(acute.round()),
                format.integer(effortChronicDays),
                format.integer(chronic.round()),
              ),
            ),
            child: Column(
              children: [
                _Line(
                  key: EffortLoadKeys.acute,
                  label: l10n.effortLoadAcute,
                  value: l10n.effortLoadPerDay(format.integer(acute.round())),
                ),
                const SizedBox(height: 6),
                _Line(
                  key: EffortLoadKeys.chronic,
                  label: l10n.effortLoadChronic,
                  value: l10n.effortLoadPerDay(format.integer(chronic.round())),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        CaptionText(l10n.effortLoadNoRatio, key: EffortLoadKeys.noRatio),
        const SizedBox(height: 10),
        CaptionText(l10n.effortLoadNote),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const new({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 2,
          children: [
            Text(label, style: theme.bodyLarge),
            Text(
              value,
              style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
