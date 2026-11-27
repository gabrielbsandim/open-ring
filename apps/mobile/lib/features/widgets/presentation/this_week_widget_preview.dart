import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/features/widgets/presentation/widget_labels.dart';
import 'package:open_ring/features/widgets/presentation/widget_previews.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

enum ThisWeekPreviewSize { small, medium, large }

class ThisWeekWidgetPreview extends StatelessWidget {
  const new({
    required this.snapshot,
    required this.now,
    this.size = ThisWeekPreviewSize.medium,
    super.key,
  });

  static const previewKey = Key('this_week_widget_preview');

  final WidgetSnapshot? snapshot;
  final DateTime now;
  final ThisWeekPreviewSize size;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final data = snapshot;
    final hasEffort =
        data != null &&
        (data.enabledModules.contains(ModuleId.effort) || data.effort != null);
    final hasGoals =
        data != null &&
        (data.enabledModules.contains(ModuleId.goals) || data.goals != null);
    final status = data != null && !data.paired
        ? (text: l10n.todayNoRing, stale: false)
        : widgetSyncStatus(format, data, now);
    final goals = data?.goals;
    final range = goals == null
        ? null
        : l10n.effortWeekRange(
            format.monthDay(goals.monday),
            format.monthDay(goals.sunday),
          );

    return WidgetPreviewFrame(
      key: previewKey,
      colors: colors,
      label: '${l10n.goalsWeekTitle}: ${status.text}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data == null || (!hasEffort && !hasGoals)) ...[
            Text(
              l10n.goalsWeekTitle,
              style: textTheme.titleSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data == null ? l10n.widgetNoData : l10n.widgetThisWeekOff,
              style: textTheme.bodyMedium?.copyWith(color: colors.textLabel),
            ),
          ] else
            _ThisWeekContent(
              snapshot: data,
              format: format,
              colors: colors,
              size: size,
              hasEffort: hasEffort,
              hasGoals: hasGoals,
              range: range,
              status: status,
            ),
        ],
      ),
    );
  }
}

class _ThisWeekContent extends StatelessWidget {
  const new({
    required this.snapshot,
    required this.format,
    required this.colors,
    required this.size,
    required this.hasEffort,
    required this.hasGoals,
    required this.range,
    required this.status,
  });

  final WidgetSnapshot snapshot;
  final MetricFormat format;
  final AppColors colors;
  final ThisWeekPreviewSize size;
  final bool hasEffort;
  final bool hasGoals;
  final String? range;
  final WidgetStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = format.l10n;
    final textTheme = Theme.of(context).textTheme;
    if (size == ThisWeekPreviewSize.small) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasEffort)
            _EffortBlock(
              snapshot: snapshot,
              format: format,
              colors: colors,
              largeNumber: true,
            )
          else
            _GoalsBlock(
              snapshot: snapshot,
              format: format,
              colors: colors,
              large: false,
            ),
          const SizedBox(height: 10),
          WidgetStatusLine(status: status, colors: colors),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 2,
          children: [
            Text(
              l10n.goalsWeekTitle,
              style: textTheme.titleSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (range != null)
              Text(
                range!,
                style: textTheme.labelSmall?.copyWith(color: colors.textLabel),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _ThisWeekBody(
          snapshot: snapshot,
          format: format,
          colors: colors,
          size: size,
          hasEffort: hasEffort,
          hasGoals: hasGoals,
        ),
        const SizedBox(height: 10),
        WidgetStatusLine(status: status, colors: colors),
      ],
    );
  }
}

class _ThisWeekBody extends StatelessWidget {
  const new({
    required this.snapshot,
    required this.format,
    required this.colors,
    required this.size,
    required this.hasEffort,
    required this.hasGoals,
  });

  final WidgetSnapshot snapshot;
  final MetricFormat format;
  final AppColors colors;
  final ThisWeekPreviewSize size;
  final bool hasEffort;
  final bool hasGoals;

  @override
  Widget build(BuildContext context) {
    if (size == ThisWeekPreviewSize.medium &&
        !context.prefersSingleColumn &&
        hasEffort &&
        hasGoals) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: _EffortBlock(
              snapshot: snapshot,
              format: format,
              colors: colors,
              largeNumber: false,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: _GoalsBlock(
              snapshot: snapshot,
              format: format,
              colors: colors,
              large: false,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasEffort)
          _EffortBlock(
            snapshot: snapshot,
            format: format,
            colors: colors,
            largeNumber: false,
          ),
        if (hasEffort && hasGoals) ...[
          const SizedBox(height: 10),
          Divider(height: 1, color: colors.track),
          const SizedBox(height: 10),
        ],
        if (hasGoals)
          _GoalsBlock(
            snapshot: snapshot,
            format: format,
            colors: colors,
            large: size == ThisWeekPreviewSize.large,
          ),
      ],
    );
  }
}

class _EffortBlock extends StatelessWidget {
  const new({
    required this.snapshot,
    required this.format,
    required this.colors,
    required this.largeNumber,
  });

  final WidgetSnapshot snapshot;
  final MetricFormat format;
  final AppColors colors;
  final bool largeNumber;

  @override
  Widget build(BuildContext context) {
    final l10n = format.l10n;
    final textTheme = Theme.of(context).textTheme;
    final effort = snapshot.paired ? snapshot.effort : null;
    final target = effort?.targetPoints ?? effortWeekPoints;
    final pointsText = effort == null
        ? l10n.widgetNoValue
        : format.integer(effort.points);
    final strengthDone = effort == null
        ? l10n.widgetNoValue
        : format.integer(effort.strengthDays);
    final strengthTarget = format.integer(
      effort?.strengthTarget ?? effortWeekStrengthDays,
    );
    final progress = effort == null || target <= 0
        ? null
        : (effort.points / target).clamp(0, 1).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AccentDot(color: colors.textPrimary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.effortTitle,
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          pointsText,
          style: numberStyle(
            largeNumber ? textTheme.headlineMedium : textTheme.titleLarge,
            color: colors.textPrimary,
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: 4),
          WidgetPreviewBar(
            value: progress,
            color: colors.activity,
            track: colors.track,
          ),
        ],
        const SizedBox(height: 4),
        Text(
          l10n.widgetEffortSummary(
            format.integer(target),
            strengthDone,
            strengthTarget,
          ),
          style: textTheme.labelSmall?.copyWith(color: colors.textLabel),
        ),
      ],
    );
  }
}

class _GoalsBlock extends StatelessWidget {
  const new({
    required this.snapshot,
    required this.format,
    required this.colors,
    required this.large,
  });

  final WidgetSnapshot snapshot;
  final MetricFormat format;
  final AppColors colors;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final l10n = format.l10n;
    final textTheme = Theme.of(context).textTheme;
    final goals = snapshot.goals;
    final tag = goals == null ? null : _goalsTag(l10n, goals);
    final showDots = large && snapshot.paired && !context.prefersSingleColumn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GoalsHeader(
          title: l10n.moduleGoalsName,
          tag: tag,
          colors: colors,
          large: large,
        ),
        const SizedBox(height: 4),
        switch (goals?.state) {
          null || WidgetGoalsState.base => Text(
            l10n.widgetThisWeekWaiting,
            style: textTheme.bodySmall?.copyWith(color: colors.textLabel),
          ),
          WidgetGoalsState.paused => Text(
            l10n.goalsWeekPausedBody,
            style: textTheme.bodySmall?.copyWith(color: colors.textLabel),
          ),
          WidgetGoalsState.hold => Text(
            l10n.goalsWeekHold,
            style: textTheme.bodySmall?.copyWith(color: colors.textLabel),
          ),
          WidgetGoalsState.recovery => Text(
            l10n.goalsWeekRecoveryBody,
            style: textTheme.bodySmall?.copyWith(color: colors.textLabel),
          ),
          WidgetGoalsState.review => Text(
            l10n.goalsWeekReviewTitle,
            style: textTheme.bodySmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          WidgetGoalsState.running => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final lever in goals!.levers.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _leverLabel(l10n, lever.kind),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            color: colors.textLabel,
                          ),
                        ),
                      ),
                      if (showDots &&
                          lever.days != null &&
                          lever.days!.isNotEmpty) ...[
                        _DotsRow(days: lever.days!, colors: colors),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        snapshot.paired
                            ? l10n.goalsWeekCount(
                                format.integer(lever.achieved),
                                format.integer(lever.goal),
                              )
                            : l10n.widgetNoValue,
                        style: numberStyle(
                          textTheme.labelSmall,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        },
      ],
    );
  }

  String _goalsTag(AppLocalizations l10n, WidgetGoals goals) =>
      switch (goals.state) {
        WidgetGoalsState.review => l10n.goalsWeekTagReview,
        WidgetGoalsState.paused => l10n.goalsWeekTagPaused,
        WidgetGoalsState.hold => l10n.goalsWeekHolding,
        WidgetGoalsState.base => l10n.goalsWeekTagBase,
        WidgetGoalsState.recovery => l10n.goalsWeekTagRecovery,
        WidgetGoalsState.running => switch ((
          goals.maintenance,
          goals.weekNumber,
          goals.blockWeeks,
        )) {
          (true, _, _) => l10n.goalsWeekTagMaintenance,
          (_, null, _) => l10n.moduleGoalsName,
          (_, final week?, null) => l10n.goalsWeekTag(week),
          (_, final week?, final total?) => l10n.goalsWeekTagOf(week, total),
        },
      };

  String _leverLabel(AppLocalizations l10n, LeverKind kind) => switch (kind) {
    LeverKind.strengthDays => l10n.goalsLeverStrength,
    LeverKind.sleepWindow => l10n.goalsLeverSleep,
    LeverKind.steps => l10n.goalsLeverSteps,
    LeverKind.effortPoints => l10n.goalsLeverPoints,
    LeverKind.wakeTime => l10n.goalsLeverWake,
  };
}

class _GoalsHeader extends StatelessWidget {
  const new({
    required this.title,
    required this.tag,
    required this.colors,
    required this.large,
  });

  final String title;
  final String? tag;
  final AppColors colors;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AccentDot(color: colors.textLabel),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            title,
            style: textTheme.labelSmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
    if (large) {
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 2,
        children: [
          label,
          if (tag != null)
            Text(
              tag!,
              style: textTheme.labelSmall?.copyWith(color: colors.textLabel),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label,
        if (tag != null)
          Text(
            tag!,
            style: textTheme.labelSmall?.copyWith(color: colors.textLabel),
          ),
      ],
    );
  }
}

class _DotsRow extends StatelessWidget {
  const new({required this.days, required this.colors});

  final List<LeverDayMark> days;
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (index, mark) in days.take(7).indexed) ...[
        if (index > 0) const SizedBox(width: 3),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: switch (mark) {
              LeverDayMark.met => colors.activity,
              LeverDayMark.open => colors.textPrimary,
              LeverDayMark.missed => colors.textLabel,
              LeverDayMark.ahead => colors.track,
            },
            shape: BoxShape.circle,
          ),
        ),
      ],
    ],
  );
}
