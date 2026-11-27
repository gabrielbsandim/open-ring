import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/presentation/hidden_numbers.dart';
import 'package:open_ring/features/body/presentation/weigh_in_sheet.dart';
import 'package:open_ring/features/body/presentation/weight_chart.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_entry_row.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class BodyKeys {
  static const settings = Key('body_settings');
  static const log = Key('body_log');
  static const range = Key('body_range');
  static const chart = Key('body_chart');
  static const rate = Key('body_rate');
  static const rateWhy = Key('body_rate_why');
  static const edit = Key('body_entry_edit');
  static const delete = Key('body_entry_delete');
  static const showMore = Key('body_show_more');
  static const hidden = Key('body_hidden');

  static Key entry(int id) => Key('body_entry_$id');
}

const _firstPage = 8;
const _nextPage = 20;

class BodyScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends ConsumerState<BodyScreen> {
  WeightRange _range = WeightRange.month;
  int _shown = _firstPage;
  int? _open;

  void _log() => unawaited(showWeighInSheet(context));

  void _toggle(int id) => setState(() => _open = _open == id ? null : id);

  Future<void> _delete(WeighIn entry) async {
    final l10n = UnitFormat.of(context, ref).l10n;
    final messenger = ScaffoldMessenger.of(context);
    final log = ref.read(weighInLogProvider.notifier);
    setState(() => _open = null);
    try {
      await log.delete(entry.id);
    } on Exception {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.bodyEntryDeleteFailed)),
      );
      return;
    }
    Future<void> restore() async {
      try {
        await log.add(
          WeighInDraft(
            at: entry.at,
            offsetMinutes: entry.offsetMinutes,
            kilograms: entry.kilograms,
            bodyFatPercent: entry.bodyFatPercent,
            waistCentimeters: entry.waistCentimeters,
            source: entry.source,
          ),
        );
      } on Exception {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.bodySheetSaveFailed)),
        );
      }
    }

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.bodyEntryDeleted),
          persist: false,
          action: SnackBarAction(
            label: l10n.bodyEntryUndo,
            onPressed: () => unawaited(restore()),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final units = UnitFormat.of(context, ref);
    final l10n = units.l10n;
    return AppPage(
      title: l10n.moduleBodyName,
      actions: [
        IconButton(
          key: BodyKeys.settings,
          tooltip: l10n.bodyModuleSettings,
          onPressed: () => context.go(AppPaths.settingsModuleBody),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
      children: _content(units, ref.watch(weightSummaryProvider)),
    );
  }

  List<Widget> _content(UnitFormat units, AsyncValue<WeightSummary?> summary) {
    final l10n = units.l10n;
    if (summary.hasError && !summary.hasValue) {
      return [BodyText(l10n.metricLoadError)];
    }
    if (!summary.hasValue) return const [];
    final value = summary.value;
    if (value == null) {
      return [
        EmptyStateCard(
          icon: Icons.monitor_weight_outlined,
          accent: AppColors.of(context).textLabel,
          title: l10n.bodyEmptyTitle,
          message: l10n.bodyEmptyText,
          actionLabel: l10n.bodyWeightLogFirst,
          actionKey: BodyKeys.log,
          onAction: _log,
        ),
      ];
    }
    final entries = ref.watch(weighInsProvider).value ?? const <WeighIn>[];
    final more = entries.length - _shown;
    final hidden = ref.watch(numbersHiddenProvider);
    return [
      if (hidden) ...[
        HiddenNumbersLabel(key: BodyKeys.hidden, l10n.bodyHiddenNote),
        const SizedBox(height: 12),
      ],
      _TrendCard(
        summary: value,
        hidden: hidden,
        range: _range,
        onRange: (range) => setState(() => _range = range),
      ),
      const TrajectoryEntryRow(from: TrajectoryEntry.body),
      const SizedBox(height: cardGap),
      ActionButton(
        key: BodyKeys.log,
        label: l10n.bodyWeightLog,
        onPressed: _log,
      ),
      const SizedBox(height: 24),
      _EntriesTitle(title: l10n.bodyEntriesTitle, count: entries.length),
      const SizedBox(height: 8),
      MetricCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final entry in entries.take(_shown))
              _EntryRow(
                key: BodyKeys.entry(entry.id),
                entry: entry,
                hidden: hidden,
                open: _open == entry.id,
                onToggle: () => _toggle(entry.id),
                onEdit: () =>
                    unawaited(showWeighInSheet(context, editing: entry)),
                onDelete: () => unawaited(_delete(entry)),
              ),
          ],
        ),
      ),
      if (more > 0) ...[
        const SizedBox(height: cardGap),
        SecondaryButton(
          key: BodyKeys.showMore,
          label: l10n.bodyShowMore(math.min(_nextPage, more)),
          onPressed: () => setState(() => _shown += _nextPage),
        ),
      ],
      const SizedBox(height: 16),
      CaptionText(l10n.bodyFootnote),
    ];
  }
}

class _TrendCard extends ConsumerWidget {
  const new({
    required this.summary,
    required this.hidden,
    required this.range,
    required this.onRange,
  });

  final WeightSummary summary;
  final bool hidden;
  final WeightRange range;
  final ValueChanged<WeightRange> onRange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final units = UnitFormat.of(context, ref);
    final l10n = units.l10n;
    final rate = hidden
        ? _direction(l10n, summary.rate)
        : _rate(units, summary.rate);
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hidden) ...[
            _numbers(theme, colors, units),
            const SizedBox(height: 14),
          ],
          SegmentedButton<WeightRange>(
            key: BodyKeys.range,
            showSelectedIcon: false,
            segments: [
              for (final option in WeightRange.values)
                ButtonSegment(
                  value: option,
                  label: Text(_label(units, option)),
                ),
            ],
            selected: {range},
            onSelectionChanged: (picked) => onRange(picked.first),
          ),
          const SizedBox(height: 14),
          WeightChart(
            key: BodyKeys.chart,
            daily: summary.daily,
            line: summary.line,
            today: ref.watch(currentDateProvider),
            range: range,
            units: units,
            band: hidden ? summary.noise : null,
          ),
          const SizedBox(height: 8),
          WeightLegend(
            trend: l10n.bodyWeightTrend,
            day: hidden ? null : l10n.bodyLegendDay,
            band: hidden ? l10n.bodyLegendBand : null,
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: colors.surfaceBorder),
          const SizedBox(height: 14),
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CaptionText(
                  hidden ? l10n.bodyDirectionTitle : l10n.bodyWeightRate,
                ),
                const SizedBox(height: 2),
                Text(
                  rate.value,
                  key: BodyKeys.rate,
                  style: numberStyle(theme.textTheme.titleMedium),
                ),
                const SizedBox(height: 4),
                CaptionText(rate.why, key: BodyKeys.rateWhy),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _numbers(ThemeData theme, AppColors colors, UnitFormat units) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.end,
    spacing: 16,
    runSpacing: 8,
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
                  style: numberStyle(theme.textTheme.headlineLarge),
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
            CaptionText(units.l10n.bodyWeightTrend),
          ],
        ),
      ),
      MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptionText(units.l10n.bodyWeightLast),
            Text(
              units.bodyWeight(summary.last.kilograms),
              style: numberStyle(theme.textTheme.titleSmall),
            ),
          ],
        ),
      ),
    ],
  );

  String _label(UnitFormat units, WeightRange option) {
    final days = option.days;
    if (days == null) return units.l10n.bodyRangeAll;
    return units.l10n.trendsRangeDays(days);
  }

  ({String value, String why}) _rate(UnitFormat units, WeightRate rate) {
    final l10n = units.l10n;
    final unit = units.weightUnit;
    String perWeek(double kilograms) =>
        units.format.signed(units.bodyWeightIn(kilograms), digits: 2);
    return switch (rate) {
      WeightRateBuilding() => _building(l10n, rate),
      WeightRateReady(stable: true, :final low, :final high) => (
        value: l10n.bodyRateStableTitle,
        why: l10n.bodyRateStableWhy(perWeek(low), perWeek(high), unit),
      ),
      WeightRateReady(perWeek: final slope, :final low, :final high) => (
        value: l10n.bodyWeightRatePerWeek(perWeek(slope), unit),
        why: l10n.bodyRateInterval(perWeek(low), perWeek(high), unit),
      ),
    };
  }
}

({String value, String why}) _building(
  AppLocalizations l10n,
  WeightRateBuilding rate,
) => (
  value: l10n.bodyRateNotYet,
  why: [
    l10n.bodyRateNeeds(weightRateMinDays, weightRateMinSpanDays),
    if (rate.daysMissing > 0) l10n.bodyRateMissingDays(rate.daysMissing),
    if (rate.spanMissing > 0) l10n.bodyRateMissingSpan(rate.spanMissing),
  ].join(' '),
);

({String value, String why}) _direction(
  AppLocalizations l10n,
  WeightRate rate,
) => switch (rate) {
  WeightRateBuilding() => _building(l10n, rate),
  WeightRateReady(stable: true) => (
    value: l10n.bodyRateStableTitle,
    why: l10n.bodyDirectionStableWhy,
  ),
  WeightRateReady() => (
    value: weightDirection(l10n, rate),
    why: l10n.bodyDirectionMovingWhy,
  ),
};

class _EntriesTitle extends StatelessWidget {
  const new({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
        ),
        const SizedBox(width: 8),
        CaptionText('$count'),
      ],
    );
  }
}

class _EntryRow extends ConsumerWidget {
  const new({
    required this.entry,
    required this.hidden,
    required this.open,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final WeighIn entry;
  final bool hidden;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final units = UnitFormat.of(context, ref);
    final l10n = units.l10n;
    final extras = hidden ? _kinds(l10n) : _extras(units);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              units.format.dayAndClock(
                                entry.at,
                                Duration(minutes: entry.offsetMinutes),
                              ),
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (extras.isNotEmpty) CaptionText(extras),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (hidden) ...[
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: colors.textLabel,
                        ),
                        const SizedBox(width: 4),
                        CaptionText(l10n.bodyEntryLogged),
                      ],
                      if (!hidden)
                        Text(
                          units.bodyWeight(entry.kilograms),
                          style: numberStyle(theme.textTheme.titleSmall),
                        ),
                      const SizedBox(width: 4),
                      Icon(
                        open
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: colors.textLabel,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    key: BodyKeys.edit,
                    label: l10n.bodyEntryEdit,
                    onPressed: onEdit,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SecondaryButton(
                    key: BodyKeys.delete,
                    label: l10n.settingsDeleteConfirm,
                    color: colors.heart,
                    onPressed: onDelete,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _kinds(AppLocalizations l10n) =>
      switch ((entry.bodyFatPercent, entry.waistCentimeters)) {
        (null, null) => '',
        (_, null) => l10n.bodyEntryWithBodyFat,
        (null, _) => l10n.bodyEntryWithWaist,
        _ => l10n.bodyEntryWithBoth,
      };

  String _extras(UnitFormat units) {
    final l10n = units.l10n;
    final bodyFat = entry.bodyFatPercent;
    final waist = entry.waistCentimeters;
    String one(double value) => units.format.decimal(value, digits: 1);
    return [
      if (bodyFat != null) l10n.bodyEntryBodyFat(one(bodyFat)),
      if (waist != null)
        l10n.bodyEntryWaist(one(units.waistIn(waist)), units.waistUnit),
    ].join(' · ');
  }
}
