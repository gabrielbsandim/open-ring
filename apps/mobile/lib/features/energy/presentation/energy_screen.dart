import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/energy/presentation/energy_evidence_sheet.dart';
import 'package:open_ring/features/energy/presentation/energy_parts.dart';
import 'package:open_ring/features/energy/presentation/energy_through_day.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

// The bar is as wide as a day this many times the Base, or as the top of the
// range when the day is already past that, so it fills as the hours pass.
const energyBarBaseDays = 1.5;

abstract final class EnergyKeys {
  static const day = Key('energy_day');
  static const time = Key('energy_day_time');
  static const range = Key('energy_day_range');
  static const middle = Key('energy_day_middle');
  static const starting = Key('energy_day_starting');
  static const bar = Key('energy_day_bar');
  static const resting = Key('energy_resting');
  static const restingRange = Key('energy_resting_range');
  static const restingBase = Key('energy_resting_base');
  static const missing = Key('energy_missing');
  static const missingTitle = Key('energy_missing_title');
  static const openProfile = Key('energy_open_profile');
  static const never = Key('energy_never');

  static Key part(EnergyPart part) => Key('energy_part_${part.name}');

  static Key partValue(EnergyPart part) =>
      Key('energy_part_value_${part.name}');

  static Key need(EnergyField field) => Key('energy_need_${field.name}');

  static Key needMissing(EnergyField field) =>
      Key('energy_need_missing_${field.name}');
}

double energyBarScale(EnergyDayEstimate day) => math.max(
  day.range.high.toDouble(),
  day.resting * energyBaseFactor * energyBarBaseDays,
);

String _partNote(AppLocalizations l10n, EnergyPart part, double value) {
  if (part == EnergyPart.workouts && value <= 0) {
    return l10n.energyPartWorkoutsNone;
  }
  return switch (part) {
    EnergyPart.base => l10n.energyPartBaseNote,
    EnergyPart.steps => l10n.energyPartStepsNote,
    EnergyPart.workouts => l10n.energyPartWorkoutsNote,
  };
}

String _fieldLabel(AppLocalizations l10n, EnergyField field) => switch (field) {
  EnergyField.birthYear => l10n.profileAge,
  EnergyField.sex => l10n.profileSex,
  EnergyField.height => l10n.profileHeight,
  EnergyField.weight => l10n.profileWeight,
};

class EnergyScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(energyGateProvider) == EnergyGate.on;
    return AppPage(
      title: l10n.energyTitle,
      subtitle: on ? l10n.energyLead : null,
      children: on ? _content(ref, l10n) : [],
    );
  }

  List<Widget> _content(WidgetRef ref, AppLocalizations l10n) {
    final loaded = ref.watch(energyNowProvider);
    if (loaded.hasError) return [BodyText(l10n.metricLoadError)];
    final now = loaded.value;
    if (now == null) return const [SizedBox(height: 96)];
    return switch (now.day) {
      EnergyDayUnderage() => const [],
      EnergyDayMissing(:final fields) => [
        _Missing(fields: fields),
        const SizedBox(height: cardGap),
        const EstimateNote(),
      ],
      final EnergyDayEstimate day => [
        _Day(day: day, asOf: now.asOf),
        const SizedBox(height: cardGap),
        _Resting(day: day),
        const SizedBox(height: cardGap),
        if (_curve(ref, day) case final curve?) ...[
          EnergyThroughDay(curve: curve, utcOffset: now.asOf.timeZoneOffset),
          const SizedBox(height: cardGap),
        ],
        ModuleFactsCard(
          key: EnergyKeys.never,
          title: l10n.energyNeverTitle,
          icon: Icons.block,
          facts: [
            l10n.energyNever1,
            l10n.energyNever2,
            l10n.energyNever3,
            l10n.energyNever4,
          ],
        ),
        const SizedBox(height: cardGap),
        EstimateNote(lead: l10n.energyStoredNote),
      ],
    };
  }
}

// The curve only when it has a line to draw and the day shows a range.
EnergyCurve? _curve(WidgetRef ref, EnergyDayEstimate day) {
  final curve = ref.watch(energyTodayCurveProvider).value;
  if (curve == null || curve.points.length < 2) return null;
  if (day.range.low < energyRowFloor) return null;
  return curve;
}

class _CardHead extends StatelessWidget {
  const new({required this.tag, this.tagKey});

  final String tag;
  final Key? tagKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        AccentTitle(
          title: l10n.tabToday,
          accent: AppColors.of(context).activity,
        ),
        CaptionText(tag, key: tagKey),
      ],
    );
  }
}

class _RangeLine extends StatelessWidget {
  const new({required this.range, required this.unit, this.rangeKey});

  final EnergyRange range;
  final String unit;
  final Key? rangeKey;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      runSpacing: 2,
      children: [
        Text(
          format.l10n.energyRowRange(
            format.integer(range.low),
            format.integer(range.high),
          ),
          key: rangeKey,
          style: numberStyle(Theme.of(context).textTheme.headlineSmall),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: CaptionText(unit),
        ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const new({required this.day, required this.asOf});

  final EnergyDayEstimate day;
  final DateTime asOf;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final range = day.range;
    final middle = energyRange(day.total, 0).low;
    return MetricCard(
      key: EnergyKeys.day,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHead(
            tag: l10n.energyRowSoFar(format.clock(asOf, asOf.timeZoneOffset)),
            tagKey: EnergyKeys.time,
          ),
          const SizedBox(height: 12),
          if (range.low < energyRowFloor)
            BodyText(l10n.energyRowStarting, key: EnergyKeys.starting),
          if (range.low >= energyRowFloor) ...[
            _RangeLine(
              range: range,
              unit: l10n.energyRowUnit,
              rangeKey: EnergyKeys.range,
            ),
            const SizedBox(height: 2),
            CaptionText(
              l10n.energyDayMiddle(format.integer(middle)),
              key: EnergyKeys.middle,
            ),
            const SizedBox(height: 16),
            _DayBar(day: day),
            const SizedBox(height: 4),
            CaptionText(l10n.energyBarNote),
            const SizedBox(height: 6),
            for (final part in EnergyPart.values)
              _PartRow(part: part, day: day),
          ],
          const SizedBox(height: 12),
          CaptionText(l10n.energyFixedNote),
        ],
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const new({required this.day});

  final EnergyDayEstimate day;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final colors = AppColors.of(context);
    final range = day.range;
    final scale = energyBarScale(day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedBar(
          key: EnergyKeys.bar,
          height: 16,
          semanticsLabel: format.l10n.energyBarSemantics(
            format.integer(range.low),
            format.integer(range.high),
          ),
          segments: [
            for (final part in EnergyPart.values)
              (
                weight: energyPartValue(day, part),
                color: energyPartColor(colors, part),
              ),
            (weight: math.max(0, scale - day.total), color: colors.track),
          ],
        ),
        const SizedBox(height: 3),
        ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, box) {
              double across(num value) => box.maxWidth * value / scale;
              return Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: EdgeInsets.only(left: across(range.low)),
                  child: _Whisker(
                    width: math.max(4, across(range.high - range.low)),
                    color: colors.textPrimary,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Whisker extends StatelessWidget {
  const new({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final end = BorderSide(color: color, width: 2);
    return SizedBox(
      width: width,
      height: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: end, right: end),
        ),
        child: Center(
          child: ColoredBox(
            color: color,
            child: const SizedBox(width: double.infinity, height: 2),
          ),
        ),
      ),
    );
  }
}

class _PartRow extends StatelessWidget {
  const new({required this.part, required this.day});

  final EnergyPart part;
  final EnergyDayEstimate day;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    final value = energyPartValue(day, part);
    return InkWell(
      key: EnergyKeys.part(part),
      onTap: () =>
          showEnergyEvidence(context, kind: energyEvidenceOf(part), day: day),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: energyPartColor(colors, part),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const SizedBox.square(dimension: 10),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    children: [
                      Text(
                        energyPartLabel(l10n, part),
                        style: theme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        energyPartText(format, value),
                        key: EnergyKeys.partValue(part),
                        style: theme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  CaptionText(_partNote(l10n, part, value)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Resting extends StatelessWidget {
  const new({required this.day});

  final EnergyDayEstimate day;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return MetricCard(
      key: EnergyKeys.resting,
      onTap: () =>
          showEnergyEvidence(context, kind: EnergyEvidence.resting, day: day),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.energyRestingTitle,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          _RangeLine(
            range: energyRange(day.resting, energyRestingMargin),
            unit: l10n.energyRestingUnit,
            rangeKey: EnergyKeys.restingRange,
          ),
          const SizedBox(height: 8),
          BodyText(l10n.energyRestingBody),
          const SizedBox(height: 8),
          CaptionText(
            l10n.energyRestingBase(format.decimal(energyBaseFactor, digits: 1)),
            key: EnergyKeys.restingBase,
          ),
        ],
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  const new({required this.fields});

  final Set<EnergyField> fields;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MetricCard(
      key: EnergyKeys.missing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHead(tag: l10n.energyMissingTag),
          const SizedBox(height: 12),
          Text(
            fields.length == 1
                ? l10n.energyMissingTitleOne
                : l10n.energyMissingTitleSeveral,
            key: EnergyKeys.missingTitle,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          BodyText(l10n.energyMissingBody),
          const SizedBox(height: 4),
          for (final field in EnergyField.values)
            _NeedRow(field: field, missing: fields.contains(field)),
          const SizedBox(height: 14),
          ActionButton(
            key: EnergyKeys.openProfile,
            label: l10n.energyOpenProfile,
            onPressed: () => context.go(AppPaths.settings),
          ),
          const SizedBox(height: 10),
          CaptionText(l10n.energyMissingSexNote),
        ],
      ),
    );
  }
}

class _NeedRow extends StatelessWidget {
  const new({required this.field, required this.missing});

  final EnergyField field;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    return Padding(
      key: EnergyKeys.need(field),
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              missing ? Icons.edit_outlined : Icons.check,
              size: 20,
              color: missing ? colors.textPrimary : colors.textLabel,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              children: [
                Text(_fieldLabel(l10n, field), style: theme.bodyLarge),
                if (missing)
                  Text(
                    l10n.energyNeedMissing,
                    key: EnergyKeys.needMissing(field),
                    style: theme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
