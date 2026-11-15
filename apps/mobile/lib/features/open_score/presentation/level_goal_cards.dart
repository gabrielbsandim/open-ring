import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/open_score/application/week_goal_providers.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/presentation/day_tag_sheet.dart';
import 'package:open_ring/features/open_score/presentation/level_block.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class LevelGoalKeys {
  static const week = Key('level_week');
  static const count = Key('level_week_count');
  static const message = Key('level_week_message');
  static const goal = Key('level_week_goal');
  static const less = Key('level_week_less');
  static const more = Key('level_week_more');
  static const forming = Key('level_week_forming');
  static const bests = Key('level_bests');
  static const bestDay = Key('level_best_day');
  static const bestWeek = Key('level_best_week');
  static const bestLevel = Key('level_best_level');

  static Key day(LocalDate date) => Key('level_week_day_${date.iso}');
}

String weekDayLabel(AppLocalizations l10n, WeekDayKind kind, String day) =>
    switch (kind) {
      WeekDayKind.met => l10n.levelWeekDayMet(day),
      WeekDayKind.missed => l10n.levelWeekDayMissed(day),
      WeekDayKind.tagged => l10n.levelWeekDayTagged(day),
      WeekDayKind.blank => l10n.levelWeekDayBlank(day),
      WeekDayKind.noLine => l10n.levelWeekDayNoLine(day),
      WeekDayKind.today => l10n.levelWeekDayToday(day),
      WeekDayKind.future => l10n.levelWeekDayFuture(day),
    };

String weekMessage(MetricFormat format, LevelWeek week) {
  final l10n = format.l10n;
  final metOn = week.metOn;
  if (metOn != null) return l10n.levelWeekMet(format.date(metOn));
  if (!week.reachable) return l10n.levelWeekOut;
  final need = l10n.levelWeekNeed(week.need);
  final todayOpen = week.days.any((day) => day.kind == WeekDayKind.today);
  if (!todayOpen) return need;
  // Japanese and Chinese sentences end in a full width stop and take no space.
  final space = need.endsWith('.') ? ' ' : '';
  return '$need$space${l10n.levelWeekTodayCounts}';
}

class WeekGoalCard extends ConsumerWidget {
  const new({required this.week, required this.history, super.key});

  final LevelWeek week;
  final DayScoreHistory history;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final goal = week.goal;
    return MetricCard(
      key: LevelGoalKeys.week,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              AccentTitle(
                title: l10n.levelWeekTitle,
                accent: colors.textPrimary,
              ),
              CaptionText(
                l10n.levelWeekRange(
                  format.monthDay(week.days.first.date),
                  format.monthDay(week.days.last.date),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          MergeSemantics(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                Text(
                  key: LevelGoalKeys.count,
                  '${week.count}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                CaptionText(l10n.levelWeekCount(goal)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final day in week.days)
                Expanded(
                  child: _Day(
                    key: LevelGoalKeys.day(day.date),
                    day: day,
                    score: history.scoredOn(day.date)?.value,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            key: LevelGoalKeys.message,
            weekMessage(format, week),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: week.met ? colors.textPrimary : colors.textSecondary,
              fontWeight: week.met ? FontWeight.w600 : null,
            ),
          ),
          const SizedBox(height: 10),
          ExcludeSemantics(
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _Legend(WeekDayKind.met, l10n.levelWeekLegendMet),
                _Legend(WeekDayKind.missed, l10n.levelWeekLegendMissed),
                _Legend(WeekDayKind.tagged, l10n.dayScoreHistoryLegendTagged),
                _Legend(WeekDayKind.today, l10n.workoutDayToday),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: colors.surfaceBorder),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.levelWeekGoalTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    CaptionText(
                      l10n.levelWeekGoalNote(weekGoalMin, weekGoalMax),
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                key: LevelGoalKeys.less,
                tooltip: l10n.levelWeekLess,
                onPressed: goal <= weekGoalMin
                    ? null
                    : () => _set(ref, goal - 1),
                icon: const Icon(Icons.remove_rounded),
              ),
              Semantics(
                liveRegion: true,
                child: SizedBox(
                  width: 40,
                  child: Text(
                    key: LevelGoalKeys.goal,
                    '$goal',
                    textAlign: TextAlign.center,
                    style: numberStyle(theme.textTheme.titleLarge),
                  ),
                ),
              ),
              IconButton.outlined(
                key: LevelGoalKeys.more,
                tooltip: l10n.levelWeekMore,
                onPressed: goal >= weekGoalMax
                    ? null
                    : () => _set(ref, goal + 1),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CaptionText(l10n.levelWeekNote),
        ],
      ),
    );
  }

  Future<void> _set(WidgetRef ref, int goal) =>
      ref.read(weekGoalProvider.notifier).set(goal);
}

class _Day extends StatelessWidget {
  const new({required this.day, required this.score, super.key});

  final WeekDay day;
  final int? score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final today = day.kind == WeekDayKind.today;
    final shown = day.kind == WeekDayKind.future ? null : score;
    return Semantics(
      container: true,
      label: weekDayLabel(format.l10n, day.kind, format.weekday(day.date)),
      value: shown == null ? null : '$shown',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Text(
              format.weekday(day.date),
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: theme.textTheme.labelSmall?.copyWith(
                color: today ? colors.textPrimary : colors.textLabel,
                fontWeight: today ? FontWeight.w700 : null,
              ),
            ),
            const SizedBox(height: 6),
            WeekMarker(kind: day.kind),
            const SizedBox(height: 6),
            Text(
              shown == null ? '' : '$shown',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: numberStyle(
                theme.textTheme.labelMedium,
                color: day.kind == WeekDayKind.tagged
                    ? colors.textLabel
                    : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WeekMarker extends StatelessWidget {
  const new({required this.kind, super.key});

  final WeekDayKind kind;

  static const size = 18.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox.square(
      dimension: size,
      child: switch (kind) {
        WeekDayKind.met => DecoratedBox(
          decoration: BoxDecoration(
            color: colors.textPrimary,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_rounded, size: 13, color: colors.surface),
        ),
        WeekDayKind.missed => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.textLabel, width: 1.5),
          ),
        ),
        WeekDayKind.tagged => CustomPaint(
          painter: DashedBorderPainter(
            color: colors.textLabel,
            radius: size / 2,
          ),
        ),
        WeekDayKind.today => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.textPrimary, width: 2),
          ),
          child: Center(child: _Dot(color: colors.textPrimary)),
        ),
        WeekDayKind.blank ||
        WeekDayKind.noLine ||
        WeekDayKind.future => Center(child: _Dot(color: colors.strongBorder)),
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const new({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 5,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

class _Legend extends StatelessWidget {
  const new(this.kind, this.label);

  final WeekDayKind kind;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Transform.scale(scale: 0.7, child: WeekMarker(kind: kind)),
      const SizedBox(width: 4),
      Flexible(child: CaptionText(label)),
    ],
  );
}

class WeekGoalFormingCard extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return MetricCard(
      key: LevelGoalKeys.forming,
      color: colors.surfaceInner,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.schedule_rounded,
              size: 20,
              color: colors.textLabel,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: BodyText(l10n.levelWeekForming)),
        ],
      ),
    );
  }
}

class BestsCard extends StatelessWidget {
  const new({required this.bests, super.key});

  final LevelBests bests;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final day = bests.day;
    final week = bests.week;
    final level = bests.level;
    return MetricCard(
      key: LevelGoalKeys.bests,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: l10n.levelBestsTitle, accent: colors.textPrimary),
          const SizedBox(height: 6),
          if (day != null)
            _Best(
              key: LevelGoalKeys.bestDay,
              title: l10n.levelBestDay,
              note: format.date(day.date),
              value: '${day.score}',
            ),
          _Best(
            key: LevelGoalKeys.bestWeek,
            title: l10n.levelBestWeek,
            note: week == null
                ? l10n.levelBestWeekNone(bestWeekMinDays)
                : l10n.levelBestWeekOf(
                    format.monthDay(week.monday),
                    format.monthDay(week.monday.addDays(6)),
                  ),
            value: week == null ? null : '${week.average}',
          ),
          if (level != null)
            _Best(
              key: LevelGoalKeys.bestLevel,
              title: l10n.levelBestLevel,
              note: format.date(level.date),
              value: levelNumber(format, level.level),
            ),
          const SizedBox(height: 8),
          CaptionText(l10n.levelBestsNote(dayScoreHistoryDays)),
        ],
      ),
    );
  }
}

class _Best extends StatelessWidget {
  const new({
    required this.title,
    required this.note,
    required this.value,
    super.key,
  });

  final String title;
  final String note;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = value;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  CaptionText(note),
                ],
              ),
            ),
            if (shown != null) ...[
              const SizedBox(width: 12),
              Text(shown, style: numberStyle(theme.textTheme.titleLarge)),
            ],
          ],
        ),
      ),
    );
  }
}
