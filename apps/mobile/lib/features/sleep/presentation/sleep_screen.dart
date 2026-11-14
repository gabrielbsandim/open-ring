import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/presentation/sync_status_banner.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_view.dart';
import 'package:open_ring/features/sleep/presentation/hypnogram.dart';
import 'package:open_ring/features/sleep/presentation/sleep_labels.dart';
import 'package:open_ring/features/sleep/presentation/sleep_score_breakdown.dart';
import 'package:open_ring/features/sleep/presentation/sleep_stage_summary.dart';

class SleepScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static Key dayKey(int index) => Key('sleep_day_$index');
  static const scoreKey = Key('sleep_score');
  static const splitNoteKey = Key('sleep_split_note');
  static const breakdownKey = Key('sleep_breakdown');
  static const emptyActionKey = Key('sleep_empty_action');

  @override
  ConsumerState<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends ConsumerState<SleepScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final week = ref.watch(sleepWeekProvider);
    final day = switch (week.value) {
      final SleepWeekView w => w.days[_indexIn(w)],
      null => null,
    };
    return AppPage(
      title: format.l10n.tabSleep,
      subtitle: day == null ? null : format.nightOf(day.date),
      onRefresh: () => refreshRing(ref),
      children: [
        const SyncStatusBanner(),
        AsyncBody(
          value: week,
          builder: (w) => _SleepBody(
            week: w,
            withoutRing: ref.watch(readsWithoutRingProvider).value ?? false,
            selected: _indexIn(w),
            onSelect: (index) => setState(() => _selected = index),
          ),
        ),
      ],
    );
  }

  int _indexIn(SleepWeekView week) =>
      (_selected ?? week.days.length - 1).clamp(0, week.days.length - 1);
}

class _SleepBody extends StatelessWidget {
  const new({
    required this.week,
    required this.withoutRing,
    required this.selected,
    required this.onSelect,
  });

  final SleepWeekView week;
  final bool withoutRing;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final day = week.days[selected];
    final night = day.night;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayPicker(week: week, selected: selected, onSelect: onSelect),
        const SizedBox(height: cardGap),
        if (night == null)
          EmptyStateCard(
            icon: Icons.bedtime_rounded,
            accent: colors.sleep,
            title: format.l10n.sleepNoNight(format.date(day.date)),
            message: withoutRing
                ? format.l10n.sleepEmptyImported
                : format.l10n.sleepEmpty,
            actionLabel: format.l10n.metricOpenRing,
            actionKey: SleepScreen.emptyActionKey,
            onAction: () => context.go(AppTab.ring.path),
          ),
        if (night != null) ...[
          _NightCard(week: week, day: day),
          const SizedBox(height: cardGap),
          MetricCard(
            key: SleepScreen.breakdownKey,
            child: SleepScoreBreakdown(
              day: day,
              goal: week.goal,
              remMeasured: week.remMeasured,
            ),
          ),
        ],
      ],
    );
  }
}

class _DayPicker extends StatelessWidget {
  const new({
    required this.week,
    required this.selected,
    required this.onSelect,
  });

  final SleepWeekView week;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: [
          for (var i = 0; i < week.days.length; i++)
            _DayButton(
              key: SleepScreen.dayKey(i),
              day: week.days[i],
              selected: i == selected,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _DayButton extends StatelessWidget {
  const new({
    required this.day,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final SleepDayView day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final score = day.scoreValue;
    final label = score == null
        ? format.l10n.sleepDayNoScore(format.date(day.date))
        : format.l10n.sleepDayScore(format.date(day.date), score);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? colors.surfaceInner : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    format.weekday(day.date),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? colors.textPrimary : colors.textLabel,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: const EdgeInsets.all(4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? colors.sleep : null,
                      border: selected
                          ? null
                          : Border.all(
                              color: colors.sleep.withValues(alpha: 0.4),
                              width: 2,
                            ),
                    ),
                    child: Text(
                      score == null ? '' : '$score',
                      style: numberStyle(
                        theme.textTheme.labelMedium,
                        color: selected
                            ? colors.onAccent
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NightCard extends StatelessWidget {
  const new({required this.week, required this.day});

  final SleepWeekView week;
  final SleepDayView day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final night = day.night!;
    final score = day.scoreValue;
    final big = numberStyle(theme.textTheme.headlineLarge);
    final split = day.splitBreak;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 12,
            children: [
              MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CaptionText(l10n.sleepAsleep),
                    Text(format.duration(night.asleep), style: big),
                    CaptionText(
                      l10n.sleepInBed(
                        format.duration(night.timeInBed),
                        nightRange(format, night),
                      ),
                    ),
                  ],
                ),
              ),
              _ScoreButton(
                score: score,
                style: big?.copyWith(color: colors.sleep),
                alignEnd: !context.prefersSingleColumn,
                onTap: () => _showBreakdown(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Hypnogram(night: night, remMeasured: week.remMeasured),
          const SizedBox(height: 12),
          SleepStageLegend(night: night, remMeasured: week.remMeasured),
          if (split != null) ...[
            const SizedBox(height: 12),
            Container(
              key: SleepScreen.splitNoteKey,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surfaceInner,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    size: 16,
                    color: colors.sleep,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BodyText(
                      l10n.sleepSplitNight(
                        day.stretches,
                        format.clock(split.start, split.utcOffset),
                        format.duration(split.duration),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showBreakdown(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppColors.of(context).surface,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: SleepScoreBreakdown(
              day: day,
              goal: week.goal,
              remMeasured: week.remMeasured,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreButton extends StatelessWidget {
  const new({
    required this.score,
    required this.style,
    required this.alignEnd,
    required this.onTap,
  });

  final int? score;
  final TextStyle? style;
  final bool alignEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = MetricFormat.of(context).l10n;
    final value = score;
    return Semantics(
      button: true,
      onTapHint: l10n.metricShowInputs,
      child: InkWell(
        key: SleepScreen.scoreKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Column(
            crossAxisAlignment: alignEnd
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              CaptionText(l10n.sleepScoreLabel),
              Text(
                value == null ? l10n.sleepScoreNone : '$value',
                style: style,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
