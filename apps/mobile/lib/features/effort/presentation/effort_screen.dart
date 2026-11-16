import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/effort/application/effort_gate.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/effort/presentation/effort_coach_card.dart';
import 'package:open_ring/features/effort/presentation/effort_evidence_sheet.dart';
import 'package:open_ring/features/effort/presentation/effort_load_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/workout/presentation/workout_entry_button.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class EffortKeys {
  static const week = Key('effort_week');
  static const weekRange = Key('effort_week_range');
  static const weekPoints = Key('effort_week_points');
  static const weekStrength = Key('effort_week_strength');
  static const weekMessage = Key('effort_week_message');
  static const pointsSheet = Key('effort_points_sheet');
  static const strengthSheet = Key('effort_strength_sheet');
  static const weekDays = Key('effort_week_days');
  static const weekSources = Key('effort_week_sources');
  static const lastSeven = Key('effort_last_seven');
  static const sessions = Key('effort_sessions');
  static const sessionsEmpty = Key('effort_sessions_empty');
  static const never = Key('effort_never');
  static const formula = Key('effort_formula_link');
  static const foot = Key('effort_foot');

  static Key session(int index) => Key('effort_session_$index');

  static Key walk(int index) => Key('effort_walk_$index');

  static Key weekDay(int index) => Key('effort_week_day_$index');
}

/// What the week still asks for, in one sentence.
String effortWeekMessage(
  MetricFormat format,
  EffortWeek week, {
  required bool empty,
}) {
  final l10n = format.l10n;
  if (empty) return l10n.effortWeekEmpty;
  final open = effortWeekPoints - week.points.round();
  final strength = week.strengthDays >= effortWeekStrengthDays;
  return switch ((open <= 0, strength)) {
    (true, true) => l10n.effortWeekBothCovered,
    (true, false) => l10n.effortWeekPointsCovered(
      format.integer(effortWeekPoints),
    ),
    (false, true) => l10n.effortWeekStrengthCovered(format.integer(open)),
    (false, false) => l10n.effortWeekOpen(format.integer(open)),
  };
}

/// Where the points of the week came from, as one line, or null with none.
String? effortWeekSources(
  MetricFormat format,
  Iterable<EffortSession> sessions,
  Iterable<EffortWalk> walks,
) {
  final l10n = format.l10n;
  final walked = walks.fold<double>(0, (sum, walk) => sum + walk.minutes);
  final parts = [
    for (final MapEntry(:key, :value) in effortPointsByType(sessions).entries)
      '${key.label(l10n)} ${format.integer(value.round())}',
    if (walked.round() >= 1)
      '${l10n.effortBriskWalking} ${format.integer(walked.round())}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// One day of the week strip, as a screen reader says it.
String effortWeekDayLabel(MetricFormat format, EffortWeekDay day) {
  final l10n = format.l10n;
  final name = format.weekday(day.date);
  final points = day.points;
  if (points == null) return l10n.effortWeekDayFuture(name);
  final value = format.integer(points.round());
  return day.strength
      ? l10n.effortWeekDayStrength(name, value)
      : l10n.effortWeekDayPoints(name, value);
}

class EffortScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(effortEnabledProvider);
    return AppPage(
      title: l10n.effortTitle,
      subtitle: on ? l10n.effortLead : null,
      children: on ? _content(ref, l10n) : [],
    );
  }

  List<Widget> _content(WidgetRef ref, AppLocalizations l10n) {
    final week = ref.watch(effortWeekProvider);
    final sessions = ref.watch(effortSessionsProvider);
    if (week.hasError || sessions.hasError) {
      return [BodyText(l10n.metricLoadError)];
    }
    final loaded = week.value;
    final all = sessions.value;
    if (loaded == null || all == null) return const [SizedBox(height: 96)];
    final ofWeek = [
      for (final session in all.reversed)
        if (session.date.compareTo(loaded.monday) >= 0) session,
    ];
    final walks = ref.watch(effortWeekWalksProvider).value ?? const [];
    final card = ref.watch(effortCoachCardProvider).value;
    final modules = ref.watch(enabledModulesProvider).value ?? const {};
    return [
      if (card != null) ...[
        Builder(
          builder: (context) => EffortCoachCardView(
            card: card,
            onTap: () => showEffortEvidence(
              context,
              kind: EffortEvidence.coach,
              yours: effortCoachYours(MetricFormat.of(context), card),
            ),
          ),
        ),
        const SizedBox(height: cardGap),
      ],
      _Week(
        week: loaded,
        empty: loaded.points <= 0 && ofWeek.isEmpty,
        days: ref.watch(effortWeekDaysProvider).value,
        today: ref.watch(currentDateProvider),
        sessions: ofWeek,
        walks: walks,
        lastSeven: ref.watch(effortLastSevenProvider).value,
        dayScore: modules.contains(ModuleId.openScore),
      ),
      const SizedBox(height: cardGap),
      _Sessions(sessions: ofWeek, walks: walks),
      const SizedBox(height: cardGap),
      if (ref.watch(effortDailyLoadProvider).value case final dailyLoad?) ...[
        EffortLoadCard(dailyLoad: dailyLoad),
        const SizedBox(height: cardGap),
      ],
      ModuleFactsCard(
        key: EffortKeys.never,
        title: l10n.effortNeverTitle,
        icon: Icons.block,
        facts: [
          l10n.effortNever1,
          l10n.effortNever2,
          l10n.effortNever3,
          l10n.effortNever4,
          l10n.effortNever5,
        ],
      ),
      const SizedBox(height: 8),
      const _FormulaLink(),
      const SizedBox(height: 8),
      CaptionText(l10n.effortFoot, key: EffortKeys.foot),
    ];
  }
}

class _FormulaLink extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: EffortKeys.formula,
        onPressed: () => unawaited(context.push(AppPaths.effortFormula)),
        icon: const Icon(Icons.receipt_long_outlined),
        label: Text(AppLocalizations.of(context).formulaLink),
      ),
    );
  }
}

class _Week extends StatelessWidget {
  const new({
    required this.week,
    required this.empty,
    required this.days,
    required this.today,
    required this.sessions,
    required this.walks,
    required this.lastSeven,
    required this.dayScore,
  });

  final EffortWeek week;
  final bool empty;
  final List<EffortWeekDay>? days;
  final LocalDate today;
  final List<EffortSession> sessions;
  final List<EffortWalk> walks;
  final double? lastSeven;
  final bool dayScore;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    final points = format.integer(week.points.round());
    final target = format.integer(effortWeekPoints);
    final days = format.integer(week.strengthDays);
    final strengthTarget = format.integer(effortWeekStrengthDays);
    final lastSeven = this.lastSeven;
    final weekDays = this.days;
    final sources = effortWeekSources(format, sessions.reversed, walks);
    return MetricCard(
      key: EffortKeys.week,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                l10n.effortWeekTitle,
                style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              CaptionText(
                l10n.effortWeekRange(
                  format.monthDay(week.monday),
                  format.monthDay(week.monday.addDays(6)),
                ),
                key: EffortKeys.weekRange,
              ),
            ],
          ),
          const SizedBox(height: 12),
          MergeSemantics(
            child: InkWell(
              key: EffortKeys.pointsSheet,
              onTap: () => showEffortEvidence(
                context,
                kind: EffortEvidence.points,
                yours: [
                  l10n.effortSheetPointsYours(points),
                  if (lastSeven != null)
                    l10n.effortLastSeven(format.integer(lastSeven.round())),
                ].join(' '),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    points,
                    key: EffortKeys.weekPoints,
                    style: theme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  CaptionText(l10n.effortWeekPoints(target)),
                  const SizedBox(height: 8),
                  ExcludeSemantics(
                    child: ProgressBar(
                      value: (week.points / effortWeekPoints).clamp(0, 1),
                      color: colors.activity,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          MergeSemantics(
            child: InkWell(
              key: EffortKeys.strengthSheet,
              onTap: () => showEffortEvidence(
                context,
                kind: EffortEvidence.strength,
                yours: l10n.effortSheetStrengthYours(days, strengthTarget),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    days,
                    key: EffortKeys.weekStrength,
                    style: theme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  CaptionText(l10n.effortWeekStrength(strengthTarget)),
                ],
              ),
            ),
          ),
          if (weekDays != null) ...[
            const SizedBox(height: 14),
            _DayStrip(days: weekDays, today: today),
            const SizedBox(height: 8),
            CaptionText(l10n.effortWeekStripNote),
          ],
          if (sources != null) ...[
            const SizedBox(height: 12),
            MergeSemantics(
              key: EffortKeys.weekSources,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CaptionText(l10n.effortWeekSourcesTitle),
                  const SizedBox(height: 2),
                  Text(
                    sources,
                    style: theme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            effortWeekMessage(format, week, empty: empty),
            key: EffortKeys.weekMessage,
            style: theme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          if (lastSeven != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceInner,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                [
                  l10n.effortLastSeven(format.integer(lastSeven.round())),
                  if (dayScore) l10n.effortLastSevenDayScore,
                ].join(' '),
                key: EffortKeys.lastSeven,
                style: theme.bodySmall?.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayStrip extends StatelessWidget {
  const new({required this.days, required this.today});

  final List<EffortWeekDay> days;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final narrow = MaterialLocalizations.of(context).narrowWeekdays;
    return Semantics(
      key: EffortKeys.weekDays,
      container: true,
      excludeSemantics: true,
      label: [for (final day in days) effortWeekDayLabel(format, day)]
          .join('. '),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, day) in days.indexed)
            Expanded(
              child: _DayCell(
                key: EffortKeys.weekDay(index),
                day: day,
                // The strip starts on Monday and the narrow names on Sunday.
                name: narrow[(index + 1) % DateTime.daysPerWeek],
                today: day.date == today,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const new({
    required this.day,
    required this.name,
    required this.today,
    super.key,
  });

  final EffortWeekDay day;
  final String name;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    final points = day.points?.round();
    final counted = points != null && points > 0;
    return Column(
      children: [
        Text(
          name,
          maxLines: 1,
          style: theme.labelSmall?.copyWith(
            color: today ? colors.textPrimary : colors.textLabel,
            fontWeight: today ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _figure(format, points),
            maxLines: 1,
            style: theme.bodyLarge?.copyWith(
              color: counted ? colors.textPrimary : colors.textLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: day.strength ? colors.textPrimary : null,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

String _figure(MetricFormat format, int? points) => switch (points) {
  null => ' ',
  0 => '·',
  _ => format.integer(points),
};

/// The load of [session] and where it came from, for its evidence sheet.
String effortSessionYours(MetricFormat format, EffortSession session) {
  final l10n = format.l10n;
  final type = session.type.label(l10n);
  final day = format.weekday(session.date);
  final minutes = format.integer(session.elapsed.inMinutes);
  final load = format.integer(session.load.value);
  final typeDefault = effortTypeDefault(session.type);
  return switch (session.load.source) {
    LoadSource.heartRate => l10n.effortSheetSessionYoursHeartRate(
      type,
      day,
      minutes,
      load,
    ),
    LoadSource.typeDefault => l10n.effortSheetSessionYoursDefault(
      type,
      day,
      minutes,
      load,
      format.decimal(
        typeDefault,
        digits: typeDefault == typeDefault.roundToDouble() ? 0 : 1,
      ),
    ),
    LoadSource.rating => l10n.effortSheetSessionYoursRating(
      type,
      day,
      minutes,
      format.integer(session.rating ?? effortMinRating),
      load,
    ),
  };
}

/// Today's verdict, the rule that fired and the numbers it read.
String effortCoachYours(MetricFormat format, EffortCoachCard card) {
  final rule = card.advice.rule;
  return format.l10n.effortSheetCoachYours(
    coachVerdictLabel(format.l10n, rule.verdict),
    format.integer(rule.number),
    coachWhy(format, card),
  );
}

class _Sessions extends StatelessWidget {
  const new({required this.sessions, required this.walks});

  final List<EffortSession> sessions;
  final List<EffortWalk> walks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    return MetricCard(
      key: EffortKeys.sessions,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.effortSessionsTitle,
            style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (sessions.isEmpty && walks.isEmpty) ...[
            BodyText(l10n.effortSessionsEmpty, key: EffortKeys.sessionsEmpty),
            const SizedBox(height: 12),
            const WorkoutEntryButton(),
          ],
          for (final (index, session) in sessions.indexed)
            _SessionRow(key: EffortKeys.session(index), session: session),
          for (final (index, walk) in walks.indexed)
            _WalkRow(key: EffortKeys.walk(index), walk: walk),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const new({required this.session, super.key});

  final EffortSession session;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final day = format.weekday(session.date);
    final minutes = format.integer(session.elapsed.inMinutes);
    final points = format.integer(session.points.equivalent.round());
    final load = format.integer(session.load.value);
    final type = session.type.label(l10n);
    final detail = session.load.source == LoadSource.typeDefault
        ? l10n.effortSessionDetailNoHeartRate(day, minutes)
        : l10n.effortSessionDetail(day, minutes);
    return _EntryRow(
      icon: session.type.icon,
      title: type,
      detail: detail,
      points: points,
      load: load,
      onTap: () => showEffortEvidence(
        context,
        kind: EffortEvidence.session,
        yours: effortSessionYours(format, session),
      ),
    );
  }
}

class _WalkRow extends StatelessWidget {
  const new({required this.walk, super.key});

  final EffortWalk walk;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final minutes = format.integer(walk.minutes.round());
    final day = format.weekday(walk.date);
    final load = format.integer(walkingLoad(walk.minutes));
    return _EntryRow(
      icon: Icons.directions_walk,
      title: l10n.effortBriskWalking,
      detail: l10n.effortWalkDetail(day, minutes),
      points: minutes,
      load: load,
      onTap: () => showEffortEvidence(
        context,
        kind: EffortEvidence.walk,
        yours: l10n.effortSheetWalkYours(day, minutes, minutes, load),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.detail,
    required this.points,
    required this.load,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String points;
  final String load;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: onTap != null,
      onTap: onTap,
      label: l10n.effortSessionSemantics(title, detail, points, load),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          // A Wrap and not a Row: at a large text scale the numbers drop under
          // the name instead of squeezing it.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: colors.textSecondary),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        CaptionText(detail),
                      ],
                    ),
                  ),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    l10n.effortSessionPoints(points),
                    style: theme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  CaptionText(l10n.effortSessionLoad(load)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
