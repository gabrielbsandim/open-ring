import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/goals/application/goal_path_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

const _minutesInDay = 1440;
const _noonMinute = 720;

abstract final class GoalWeekCardKeys {
  static const card = Key('goal_week_card');
  static const open = Key('goal_week_card_open');
  static const base = Key('goal_week_card_base');
  static const paused = Key('goal_week_card_paused');
  static const recovery = Key('goal_week_card_recovery');
  static const hold = Key('goal_week_card_hold');

  static Key lever(LeverKind kind) => Key('goal_week_card_lever_${kind.name}');
  static Key count(LeverKind kind) => Key('goal_week_card_count_${kind.name}');
}

/// The card on Today with its gap, or nothing while no goal is under way.
class GoalWeekCardSlot extends ConsumerWidget {
  const new({this.padding = const EdgeInsets.only(bottom: cardGap), super.key});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(goalWeekProvider).value;
    if (week == null || week is GoalWeekOff || week is GoalWeekNoGoal) {
      return const SizedBox.shrink();
    }
    return Padding(padding: padding, child: const GoalWeekCard(onToday: true));
  }
}

/// "This week": the levers of the week, or the state that holds them.
class GoalWeekCard extends ConsumerWidget {
  const new({required this.onToday, super.key});

  /// On Today the card leads to the goal screen; there it is the plan itself.
  final bool onToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final title = Theme.of(context).textTheme.titleMedium;
    final body = switch (ref.watch(goalWeekProvider).value) {
      null || GoalWeekOff() || GoalWeekNoGoal() => null,
      GoalWeekHold() => (
        tag: null,
        children: [BodyText(l10n.goalsWeekHold, key: GoalWeekCardKeys.hold)],
      ),
      GoalWeekBase(:final goal, :final rate) => (
        tag: l10n.goalsWeekTagBase,
        children: _base(l10n, title, goal, rate),
      ),
      GoalWeekPaused(:final goal, :final until, :final over) => (
        tag: l10n.goalsWeekTagPaused,
        children: [
          Text(
            _pauseTitle(format, until: until, over: over),
            key: GoalWeekCardKeys.paused,
            style: title,
          ),
          const SizedBox(height: 4),
          BodyText(l10n.goalsWeekPausedBody),
          for (final lever in goal.levers)
            _LeverRow(lever: lever, progress: null, format: format),
          const SizedBox(height: 10),
          CaptionText(l10n.goalsWeekPausedNote),
        ],
      ),
      GoalWeekRecovery() => (
        tag: l10n.goalsWeekTagRecovery,
        children: [
          Text(
            l10n.goalsWeekRecoveryTitle,
            key: GoalWeekCardKeys.recovery,
            style: title,
          ),
          const SizedBox(height: 4),
          BodyText(l10n.goalsWeekRecoveryBody),
          const SizedBox(height: 10),
          CaptionText(l10n.goalsWeekRecoveryNote),
        ],
      ),
      GoalWeekRunning(:final goal, :final monday, :final week, :final levers) =>
        (
          tag: _weekTag(ref, l10n, goal, week),
          children: [
            CaptionText(
              l10n.goalsWeekPlanOf(
                goalKindName(l10n, goal.kind),
                format.monthDay(monday),
                format.monthDay(monday.addDays(6)),
              ),
            ),
            for (final progress in levers)
              _LeverRow(
                lever: progress.lever,
                progress: progress,
                format: format,
              ),
            if (levers.any((progress) => progress.days != null)) ...[
              const SizedBox(height: 12),
              _Legend(l10n: l10n),
            ],
            const SizedBox(height: 10),
            CaptionText(l10n.goalsWeekNote),
          ],
        ),
    };
    if (body == null) return const SizedBox.shrink();
    void open() => context.go(AppPaths.goals);
    return MetricCard(
      key: GoalWeekCardKeys.card,
      onTap: onToday ? open : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              AccentTitle(
                title: l10n.goalsWeekTitle,
                accent: AppColors.of(context).textPrimary,
              ),
              if (body.tag case final tag?) CaptionText(tag),
            ],
          ),
          const SizedBox(height: 8),
          ...body.children,
          if (onToday) ...[
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: GoalWeekCardKeys.open,
                onPressed: open,
                child: Text(l10n.goalsWeekOpen),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _weekTag(WidgetRef ref, AppLocalizations l10n, Goal goal, int week) {
    if (goal.kind != GoalKind.loseFat) return l10n.goalsWeekTag(week);
    final block = ref.watch(goalPathProvider).value?.path.block;
    if (block == null) return l10n.goalsWeekTag(week);
    return l10n.goalsWeekTagOf(week, block.weeks);
  }

  String _pauseTitle(
    MetricFormat format, {
    required LocalDate? until,
    required bool over,
  }) {
    final l10n = format.l10n;
    if (over) return l10n.goalsWeekPauseOver;
    if (until == null) return l10n.goalsWeekHolding;
    return l10n.goalsWeekHoldingUntil(format.monthDay(until));
  }

  List<Widget> _base(
    AppLocalizations l10n,
    TextStyle? title,
    Goal goal,
    WeightRate? rate,
  ) {
    if (goal.kind != GoalKind.loseFat) {
      return [
        BodyText(
          l10n.goalsWeekBaseOther(goalBaselineMinDays),
          key: GoalWeekCardKeys.base,
        ),
      ];
    }
    final weighed = switch (rate) {
      WeightRateBuilding(:final daysMissing) => weightRateMinDays - daysMissing,
      WeightRateReady() => weightRateMinDays,
      null => 0,
    };
    return [
      Text(l10n.goalsWeekBaseTitle, style: title),
      const SizedBox(height: 4),
      CaptionText(
        l10n.goalsWeekBaseCount(
          weighed,
          weightRateMinDays,
          weightRateMinSpanDays,
        ),
        key: GoalWeekCardKeys.base,
      ),
      const SizedBox(height: 6),
      ExcludeSemantics(
        child: LinearProgressIndicator(
          value: (weighed / weightRateMinDays).clamp(0, 1).toDouble(),
        ),
      ),
      const SizedBox(height: 10),
      BodyText(
        l10n.goalsWeekBaseBody(weightRateMinDays, weightRateMinSpanDays),
      ),
    ];
  }
}

String goalKindName(AppLocalizations l10n, GoalKind kind) => switch (kind) {
  GoalKind.loseFat => l10n.goalsPickLoseFat,
  GoalKind.getFitter => l10n.goalsPickGetFitter,
  GoalKind.sleepBetter => l10n.goalsPickSleepBetter,
};

String leverName(AppLocalizations l10n, LeverKind kind) => switch (kind) {
  LeverKind.strengthDays => l10n.goalsLeverStrength,
  LeverKind.sleepWindow => l10n.goalsLeverSleep,
  LeverKind.steps => l10n.goalsLeverSteps,
  LeverKind.effortPoints => l10n.goalsLeverPoints,
  LeverKind.wakeTime => l10n.goalsLeverWake,
};

String leverTarget(MetricFormat format, Lever lever) {
  final l10n = format.l10n;
  final days = format.integer(goalDailyFitDays);
  return switch (lever.kind) {
    LeverKind.strengthDays => l10n.goalsLeverStrengthTarget(
      format.integer(lever.target),
    ),
    LeverKind.sleepWindow => l10n.goalsLeverSleepTarget(
      _clock(format, lever.target + _noonMinute),
      days,
    ),
    LeverKind.steps => l10n.goalsLeverStepsTarget(
      format.integer(lever.target),
      days,
    ),
    LeverKind.effortPoints => l10n.goalsLeverPointsTarget(
      format.integer(lever.target),
    ),
    LeverKind.wakeTime => l10n.goalsLeverWakeTarget(
      _clock(format, lever.target),
      days,
    ),
  };
}

// A wall clock time with no date, so a fixed UTC day keeps it free of any
// time zone or daylight saving shift.
String _clock(MetricFormat format, int minutes) {
  final wall = minutes % _minutesInDay;
  return format.clock(
    DateTime.utc(2000, 1, 1, wall ~/ 60, wall % 60),
    Duration.zero,
  );
}

int _need(Lever lever) => switch (lever.cadence) {
  LeverCadence.daily => goalDailyFitDays,
  LeverCadence.weekly => lever.target,
};

IconData _icon(LeverKind kind) => switch (kind) {
  LeverKind.strengthDays => Icons.fitness_center,
  LeverKind.sleepWindow => Icons.bedtime_outlined,
  LeverKind.steps => Icons.directions_walk,
  LeverKind.effortPoints => Icons.bolt,
  LeverKind.wakeTime => Icons.alarm,
};

class _LeverRow extends StatelessWidget {
  const new({
    required this.lever,
    required this.progress,
    required this.format,
  });

  final Lever lever;

  /// Null while the plan holds: the lever shows as a reminder, with no count.
  final LeverProgress? progress;
  final MetricFormat format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = format.l10n;
    final counted = progress;
    final need = _need(lever);
    final count = counted == null
        ? null
        : Text(
            l10n.goalsWeekCount(
              format.integer(counted.achieved),
              format.integer(need),
            ),
            key: GoalWeekCardKeys.count(lever.kind),
            style: numberStyle(theme.textTheme.titleMedium),
          );
    // Large text leaves no room beside the target, so the count goes under it.
    final below = context.prefersSingleColumn;
    return Padding(
      key: GoalWeekCardKeys.lever(lever.kind),
      padding: const EdgeInsets.only(top: 12),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _icon(lever.kind),
              color: AppColors.of(context).textLabel,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    leverName(l10n, lever.kind),
                    style: theme.textTheme.bodyLarge,
                  ),
                  CaptionText(leverTarget(format, lever)),
                  if (counted != null) ...[
                    const SizedBox(height: 6),
                    _Marks(progress: counted, need: need),
                  ],
                  if (below && count != null) ...[
                    const SizedBox(height: 4),
                    count,
                  ],
                ],
              ),
            ),
            if (!below && count != null) ...[const SizedBox(width: 12), count],
          ],
        ),
      ),
    );
  }
}

class _Marks extends StatelessWidget {
  const new({required this.progress, required this.need});

  final LeverProgress progress;
  final int need;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final marks = progress.days ?? _strength(progress);
    if (marks != null) {
      return ExcludeSemantics(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final mark in marks) _Dot(mark: mark)],
        ),
      );
    }
    return ExcludeSemantics(
      child: LinearProgressIndicator(
        value: need <= 0
            ? 0
            : (progress.achieved / need).clamp(0, 1).toDouble(),
        backgroundColor: colors.track,
        color: colors.textPrimary,
      ),
    );
  }

  // Strength days are few, so each one gets a dot; points get a bar.
  List<LeverDayMark>? _strength(LeverProgress progress) {
    if (progress.lever.kind != LeverKind.strengthDays) return null;
    return [
      for (var i = 0; i < need; i++)
        if (i < progress.achieved) LeverDayMark.met else LeverDayMark.ahead,
    ];
  }
}

class _Legend extends StatelessWidget {
  const new({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (mark, label) in [
          (LeverDayMark.met, l10n.goalsWeekMarkMet),
          (LeverDayMark.missed, l10n.goalsWeekMarkMissed),
          (LeverDayMark.open, l10n.goalsWeekMarkOpen),
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(child: _Dot(mark: mark)),
              const SizedBox(width: 6),
              Flexible(child: CaptionText(label)),
            ],
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const new({required this.mark});

  final LeverDayMark mark;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (size, fill, border) = switch (mark) {
      LeverDayMark.met => (10.0, colors.textPrimary, null),
      LeverDayMark.missed => (6.0, colors.strongBorder, null),
      LeverDayMark.open => (10.0, null, colors.textPrimary),
      LeverDayMark.ahead => (10.0, null, colors.track),
    };
    return SizedBox.square(
      dimension: 10,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: border == null
                ? null
                : Border.all(color: border, width: 1.5),
          ),
        ),
      ),
    );
  }
}
