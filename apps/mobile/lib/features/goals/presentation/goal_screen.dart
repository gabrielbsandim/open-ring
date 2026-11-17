import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/presentation/hidden_numbers.dart';
import 'package:open_ring/features/goals/application/goal_path_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_path.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/goals/presentation/goal_path_chart.dart';
import 'package:open_ring/features/goals/presentation/goal_week_card.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class GoalScreenKeys {
  static const off = Key('goal_screen_off');
  static const noGoal = Key('goal_screen_no_goal');
  static const pick = Key('goal_screen_pick');
  static const hold = Key('goal_screen_hold');
  static const recovery = Key('goal_screen_recovery');
  static const path = Key('goal_screen_path');
  static const chart = Key('goal_screen_chart');
  static const start = Key('goal_screen_start');
  static const now = Key('goal_screen_now');
  static const reference = Key('goal_screen_reference');
  static const rate = Key('goal_screen_rate');
  static const arrival = Key('goal_screen_arrival');
  static const hidden = Key('goal_screen_hidden');
  static const baseNote = Key('goal_screen_base_note');
  static const noWeight = Key('goal_screen_no_weight');
}

/// How far along the goal is, as the path card needs it.
enum _Stage { base, running, paused }

class GoalScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final week = ref.watch(goalWeekProvider);
    final title = l10n.goalsScreenTitle;
    if (week.hasError) {
      return AppPage(title: title, children: [BodyText(l10n.metricLoadError)]);
    }
    final loaded = week.value;
    if (loaded == null) return AppPage(title: title, children: const []);
    return switch (loaded) {
      GoalWeekOff() => AppPage(
        title: title,
        children: [BodyText(l10n.goalsScreenOff, key: GoalScreenKeys.off)],
      ),
      GoalWeekNoGoal() => _noGoal(context, l10n),
      GoalWeekHold(:final goal) => _goalPage(
        l10n,
        goal,
        subtitle: null,
        body: [
          MetricCard(
            key: GoalScreenKeys.hold,
            child: BodyText(l10n.goalsScreenHold),
          ),
        ],
      ),
      GoalWeekBase(:final goal) => _goalPage(
        l10n,
        goal,
        subtitle: goal.kind == GoalKind.loseFat
            ? l10n.goalsScreenBase
            : l10n.goalsScreenBaseOther(goalBaselineMinDays),
        body: _body(l10n, goal, _Stage.base),
      ),
      GoalWeekPaused(:final goal, :final until, :final over) => _goalPage(
        l10n,
        goal,
        subtitle: _pausedLine(format, goal, until: until, over: over),
        body: _body(l10n, goal, _Stage.paused),
      ),
      GoalWeekRecovery(:final goal, :final week) => _goalPage(
        l10n,
        goal,
        subtitle: _weekLine(ref, format, goal, week),
        body: [
          CaptionText(l10n.goalsScreenRecovery, key: GoalScreenKeys.recovery),
          const SizedBox(height: 12),
          ..._body(l10n, goal, _Stage.running),
        ],
      ),
      GoalWeekRunning(:final goal, :final week) => _goalPage(
        l10n,
        goal,
        subtitle: _weekLine(ref, format, goal, week),
        body: _body(l10n, goal, _Stage.running),
      ),
    };
  }

  Widget _noGoal(BuildContext context, AppLocalizations l10n) => AppPage(
    title: l10n.goalsScreenTitle,
    subtitle: l10n.goalsScreenNoGoalLead,
    children: [
      MetricCard(
        key: GoalScreenKeys.noGoal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.goalsPickNone,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            BodyText(l10n.goalsScreenNoGoalBody),
            const SizedBox(height: 14),
            ActionButton(
              buttonKey: GoalScreenKeys.pick,
              label: l10n.goalsScreenPick,
              onPressed: () => unawaited(context.push(AppPaths.goalsPick)),
            ),
            const SizedBox(height: 10),
            CaptionText(
              l10n.goalsScreenNoGoalNote,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _goalPage(
    AppLocalizations l10n,
    Goal goal, {
    required String? subtitle,
    required List<Widget> body,
  }) => AppPage(
    title: goalKindName(l10n, goal.kind),
    subtitle: subtitle,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...body,
          const SizedBox(height: 16),
          if (goal.kind == GoalKind.loseFat) ...[
            CaptionText(l10n.goalsScreenFootWeight),
            const SizedBox(height: 4),
          ],
          CaptionText(l10n.goalsScreenFoot),
        ],
      ),
    ],
  );

  List<Widget> _body(AppLocalizations l10n, Goal goal, _Stage stage) => [
    if (goal.kind != GoalKind.loseFat)
      MetricCard(
        key: GoalScreenKeys.noWeight,
        child: BodyText(l10n.goalsScreenNoWeight),
      ),
    if (goal.kind == GoalKind.loseFat) _PathCard(stage: stage),
    const SizedBox(height: cardGap),
    const GoalWeekCard(onToday: false),
  ];

  String _weekLine(WidgetRef ref, MetricFormat format, Goal goal, int week) {
    final l10n = format.l10n;
    final block = ref.watch(goalPathProvider).value?.path.block;
    if (goal.kind != GoalKind.loseFat || block == null) {
      return l10n.goalsScreenWeekOther(week);
    }
    return l10n.goalsScreenWeek(
      week,
      block.weeks,
      format.monthDay(block.start),
      format.monthDay(block.end),
      goalMaintenanceWeeks,
    );
  }

  String _pausedLine(
    MetricFormat format,
    Goal goal, {
    required LocalDate? until,
    required bool over,
  }) {
    final l10n = format.l10n;
    if (until == null) return l10n.goalsScreenPaused;
    if (!over) return l10n.goalsScreenPausedUntil(format.date(until));
    if (goal.kind == GoalKind.loseFat) {
      return l10n.goalsScreenPauseOverWeight(format.date(until));
    }
    return l10n.goalsScreenPauseOver(format.date(until));
  }
}

class _PathCard extends ConsumerWidget {
  const new({required this.stage});

  final _Stage stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = UnitFormat.of(context, ref);
    final l10n = units.l10n;
    final view = ref.watch(goalPathProvider);
    if (view.hasError) return BodyText(l10n.metricLoadError);
    final loaded = view.value;
    if (loaded == null) return const SizedBox(height: 96);
    final hidden = ref.watch(numbersHiddenProvider);
    return MetricCard(
      key: GoalScreenKeys.path,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: hidden
            ? _hidden(context, units, loaded.path)
            : _shown(context, units, loaded),
      ),
    );
  }

  bool get _paused => stage == _Stage.paused;

  Widget _title(BuildContext context, UnitFormat units, GoalPath path) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    children: [
      Text(
        units.l10n.goalsPathTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (stage != _Stage.base)
        CaptionText(units.l10n.goalsPathAsOf(units.format.monthDay(path.on))),
    ],
  );

  List<Widget> _hidden(BuildContext context, UnitFormat units, GoalPath path) {
    final l10n = units.l10n;
    final rate = path.weightRate;
    return [
      _title(context, units, path),
      const SizedBox(height: 10),
      HiddenNumbersLabel(key: GoalScreenKeys.hidden, l10n.bodyHiddenNote),
      const SizedBox(height: 6),
      _SheetRow(
        key: GoalScreenKeys.rate,
        title: l10n.bodyDirectionTitle,
        value: rate == null
            ? l10n.bodyDirectionNone
            : weightDirection(l10n, rate),
        detail: stage == _Stage.base ? null : _stateText(l10n, path),
        onTap: () => _open(context, GoalEvidence.rate, l10n.bodyHiddenNote),
      ),
    ];
  }

  List<Widget> _shown(
    BuildContext context,
    UnitFormat units,
    GoalPathView view,
  ) {
    final l10n = units.l10n;
    final path = view.path;
    final block = path.block;
    final startKg = path.startKg;
    final base = stage == _Stage.base;
    return [
      _title(context, units, path),
      if (!base && block != null && startKg != null) ...[
        const SizedBox(height: 12),
        GoalPathChart(
          key: GoalScreenKeys.chart,
          view: view,
          block: block,
          startKg: startKg,
          units: units,
          label: _chartLabel(units, path, block, startKg),
        ),
        const SizedBox(height: 8),
        CaptionText(
          path.referenceKg == null
              ? l10n.goalsPathLegendNoReference
              : l10n.goalsPathLegend,
        ),
      ],
      const SizedBox(height: 12),
      _tiles(context, units, path, base: base),
      Divider(height: 24, color: AppColors.of(context).surfaceBorder),
      _rateRow(context, units, path),
      if (path.referenceKg != null && !base) _arrivalRow(context, units, path),
      if (base) ...[
        const SizedBox(height: 8),
        CaptionText(l10n.goalsPathBaseNote, key: GoalScreenKeys.baseNote),
      ],
    ];
  }

  String _chartLabel(
    UnitFormat units,
    GoalPath path,
    GoalBlock block,
    double startKg,
  ) {
    final l10n = units.l10n;
    final trend = path.trendKg;
    final reference = path.referenceKg;
    return [
      l10n.goalsPathChartLabel(
        units.bodyWeight(startKg),
        units.format.date(block.start),
        units.format.date(block.end),
      ),
      if (trend != null)
        l10n.goalsPathChartTrend(
          units.bodyWeight(trend),
          units.format.date(path.on),
        ),
      if (reference != null)
        l10n.goalsPathChartReference(units.bodyWeight(reference)),
    ].join(' ');
  }

  Widget _tiles(
    BuildContext context,
    UnitFormat units,
    GoalPath path, {
    required bool base,
  }) {
    final l10n = units.l10n;
    final format = units.format;
    final start = path.startKg;
    final trend = path.trendKg;
    final reference = path.referenceKg;
    final rate = path.rate;
    final startDate = path.block?.start ?? path.on;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Tile(
            key: GoalScreenKeys.start,
            label: l10n.goalsPathStart(format.monthDay(startDate)),
            value: start == null
                ? l10n.goalsPathNoTrend
                : units.bodyWeight(start),
            onTap: () => _open(
              context,
              GoalEvidence.trend,
              goalEvidenceYours(
                units,
                GoalEvidence.trend,
                path,
                paused: _paused,
              ),
            ),
          ),
        ),
        Expanded(
          child: base
              ? _Tile(
                  key: GoalScreenKeys.now,
                  label: l10n.goalsPathRate,
                  value: rate == null
                      ? l10n.goalsPathRateNotYet
                      : l10n.goalsPathRateValue(goalRateAmount(units, rate.kg)),
                  onTap: () => _openRate(context, units, path),
                )
              : _Tile(
                  key: GoalScreenKeys.now,
                  label: l10n.goalsPathNow(format.monthDay(path.on)),
                  value: trend == null
                      ? l10n.goalsPathNoTrend
                      : units.bodyWeight(trend),
                  onTap: () => _open(
                    context,
                    GoalEvidence.trend,
                    goalEvidenceYours(
                      units,
                      GoalEvidence.trend,
                      path,
                      paused: _paused,
                    ),
                  ),
                ),
        ),
        Expanded(
          child: reference == null
              ? _Tile(
                  key: GoalScreenKeys.reference,
                  label: l10n.goalsPathPace,
                  value: l10n.goalsPathPaceValue(
                    goalPercent(format, path.targetPercent),
                  ),
                  onTap: () => _openRate(context, units, path),
                )
              : _Tile(
                  key: GoalScreenKeys.reference,
                  label: l10n.goalsPathReference,
                  value: units.bodyWeight(reference),
                  onTap: () => _open(
                    context,
                    GoalEvidence.arrival,
                    goalEvidenceYours(
                      units,
                      GoalEvidence.arrival,
                      path,
                      paused: _paused,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _rateRow(BuildContext context, UnitFormat units, GoalPath path) {
    final l10n = units.l10n;
    final format = units.format;
    final rate = path.rate;
    return _SheetRow(
      key: GoalScreenKeys.rate,
      title: l10n.goalsPathRate,
      value: rate == null
          ? l10n.goalsPathRateNotYet
          : l10n.goalsPathRateValue(goalRateAmount(units, rate.kg)),
      detail: rate == null
          ? l10n.goalsPathRateNeeds(weightRateMinDays, weightRateMinSpanDays)
          : '${l10n.goalsPathRateDetail(goalPercent(format, rate.percent), goalPercent(format, rate.percentLow), goalPercent(format, rate.percentHigh), goalPercent(format, path.targetPercent))} '
                '${_stateText(l10n, path)}',
      onTap: () => _openRate(context, units, path),
    );
  }

  Widget _arrivalRow(BuildContext context, UnitFormat units, GoalPath path) {
    final l10n = units.l10n;
    final format = units.format;
    final arrival = path.arrival;
    final reference = path.referenceKg;
    final trend = path.trendKg;
    final reached = reference != null && trend != null && trend <= reference;
    final shown = switch (arrival) {
      _ when _paused => (
        value: l10n.goalsPathArrivalPaused,
        detail: l10n.goalsPathArrivalPausedDetail,
      ),
      _ when reached => (
        value: l10n.goalsPathArrivalReached,
        detail: l10n.goalsPathArrivalReachedDetail,
      ),
      null => (
        value: l10n.goalsPathArrivalNone,
        detail: l10n.goalsPathArrivalNoneDetail,
      ),
      final range => (
        value: goalArrivalText(format, range),
        detail: l10n.goalsPathArrivalDetail(
          units.bodyWeight(reference ?? 0),
          goalArrivalText(format, range),
        ),
      ),
    };
    return _SheetRow(
      key: GoalScreenKeys.arrival,
      title: l10n.goalsPathArrival,
      value: shown.value,
      detail: shown.detail,
      onTap: () => _open(
        context,
        GoalEvidence.arrival,
        goalEvidenceYours(units, GoalEvidence.arrival, path, paused: _paused),
      ),
    );
  }

  void _openRate(BuildContext context, UnitFormat units, GoalPath path) =>
      _open(
        context,
        GoalEvidence.rate,
        goalEvidenceYours(units, GoalEvidence.rate, path, paused: _paused),
      );

  void _open(BuildContext context, GoalEvidence kind, String yours) =>
      unawaited(showGoalEvidence(context, kind: kind, yours: yours));
}

String _stateText(AppLocalizations l10n, GoalPath path) => switch (path.state) {
  PathState.building => l10n.goalsPathStateBuilding,
  PathState.above when path.overTheCap => l10n.goalsPathStateCap,
  PathState.above => l10n.goalsPathStateAbove,
  PathState.onTrack => l10n.goalsPathStateOnTrack,
  PathState.below => l10n.goalsPathStateBelow,
};

class _Tile extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CaptionText(label),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: numberStyle(Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SheetRow extends StatelessWidget {
  const new({
    required this.title,
    required this.value,
    required this.detail,
    required this.onTap,
    super.key,
  });

  final String title;
  final String value;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final text = detail;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: MergeSemantics(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 12,
                          children: [
                            Text(title, style: theme.textTheme.bodyLarge),
                            Text(
                              value,
                              style: numberStyle(theme.textTheme.titleMedium),
                            ),
                          ],
                        ),
                        if (text != null) ...[
                          const SizedBox(height: 4),
                          CaptionText(text),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.textLabel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
