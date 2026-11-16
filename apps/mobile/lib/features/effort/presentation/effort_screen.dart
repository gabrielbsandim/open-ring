import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/effort/application/effort_gate.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/effort/presentation/effort_coach_card.dart';
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
  static const lastSeven = Key('effort_last_seven');
  static const sessions = Key('effort_sessions');
  static const sessionsEmpty = Key('effort_sessions_empty');
  static const never = Key('effort_never');
  static const foot = Key('effort_foot');

  static Key session(int index) => Key('effort_session_$index');
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
    final card = ref.watch(effortCoachCardProvider).value;
    final modules = ref.watch(enabledModulesProvider).value ?? const {};
    return [
      if (card != null) ...[
        EffortCoachCardView(card: card),
        const SizedBox(height: cardGap),
      ],
      _Week(
        week: loaded,
        empty: loaded.points <= 0 && ofWeek.isEmpty,
        lastSeven: ref.watch(effortLastSevenProvider).value,
        dayScore: modules.contains(ModuleId.openScore),
      ),
      const SizedBox(height: cardGap),
      _Sessions(sessions: ofWeek),
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
      const SizedBox(height: 16),
      CaptionText(l10n.effortFoot, key: EffortKeys.foot),
    ];
  }
}

class _Week extends StatelessWidget {
  const new({
    required this.week,
    required this.empty,
    required this.lastSeven,
    required this.dayScore,
  });

  final EffortWeek week;
  final bool empty;
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
          const SizedBox(height: 14),
          MergeSemantics(
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

class _Sessions extends StatelessWidget {
  const new({required this.sessions});

  final List<EffortSession> sessions;

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
          if (sessions.isEmpty) ...[
            BodyText(l10n.effortSessionsEmpty, key: EffortKeys.sessionsEmpty),
            const SizedBox(height: 12),
            const WorkoutEntryButton(),
          ],
          for (final (index, session) in sessions.indexed)
            _SessionRow(key: EffortKeys.session(index), session: session),
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
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    final day = format.weekday(session.date);
    final minutes = format.integer(session.elapsed.inMinutes);
    final points = format.integer(session.points.equivalent.round());
    final load = format.integer(session.load.value);
    final type = session.type.label(l10n);
    final detail = session.load.source == LoadSource.typeDefault
        ? l10n.effortSessionDetailNoHeartRate(day, minutes)
        : l10n.effortSessionDetail(day, minutes);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: l10n.effortSessionSemantics(type, detail, points, load),
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
                Icon(session.type.icon, color: colors.textSecondary),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type,
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
                  style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                CaptionText(l10n.effortSessionLoad(load)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
