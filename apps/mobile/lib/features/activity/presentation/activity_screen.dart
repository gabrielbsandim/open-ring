import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/application/activity_view.dart';
import 'package:open_ring/features/activity/presentation/hourly_steps_chart.dart';
import 'package:open_ring/features/ring/presentation/sync_status_banner.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/workout/presentation/recent_workouts_card.dart';
import 'package:open_ring/features/workout/presentation/workout_entry_button.dart';

abstract final class ActivityKeys {
  static const steps = Key('activity_steps');
  static const hourly = Key('activity_hourly');
  static const energy = Key('activity_energy');
  static const distance = Key('activity_distance');
  static const week = Key('activity_week');
  static const emptyAction = Key('activity_empty_action');

  static Key day(int index) => Key('activity_day_$index');
}

class ActivityScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    return AppPage(
      title: format.l10n.tabActivity,
      subtitle: format.l10n.tabToday,
      onRefresh: () => refreshRing(ref),
      children: [
        const SyncStatusBanner(),
        AsyncBody(
          value: ref.watch(activityDayProvider),
          builder: (view) => _ActivityBody(view: view),
        ),
        const SizedBox(height: cardGap),
        const RecentWorkoutsCard(),
        const SizedBox(height: cardGap),
        const WorkoutEntryButton(),
      ],
    );
  }
}

class _ActivityBody extends ConsumerWidget {
  const new({required this.view});

  final ActivityDayView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final units = UnitFormat.of(context, ref);
    final format = units.format;
    final l10n = format.l10n;
    if (view.isEmpty) {
      return EmptyStateCard(
        icon: Icons.directions_walk_rounded,
        accent: colors.activity,
        message: l10n.activityEmpty,
        actionLabel: l10n.metricOpenRing,
        actionKey: ActivityKeys.emptyAction,
        onAction: () => context.go(AppTab.ring.path),
      );
    }
    final today = view.today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepsCard(view: view),
        const SizedBox(height: cardGap),
        AdaptiveColumns(
          first: _Tile(
            key: ActivityKeys.energy,
            label: l10n.activityActiveEnergy,
            value: today == null
                ? l10n.metricNoReading
                : l10n.activityKcal(format.integer(today.activeKilocalories)),
          ),
          second: _Tile(
            key: ActivityKeys.distance,
            label: l10n.activityDistance,
            value: today == null
                ? l10n.metricNoReading
                : units.distanceText(today.distanceMeters),
          ),
        ),
        const SizedBox(height: cardGap),
        _WeekCard(view: view),
        const SizedBox(height: 16),
        CaptionText(l10n.activityEstimateNote),
      ],
    );
  }
}

class _StepsCard extends StatelessWidget {
  const new({required this.view});

  final ActivityDayView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final steps = view.today?.steps ?? 0;
    final goal = format.integer(view.stepGoal);
    final peak = view.peak;
    return MetricCard(
      key: ActivityKeys.steps,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: l10n.activitySteps, accent: colors.activity),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            runSpacing: 4,
            children: [
              MergeSemantics(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 6,
                  children: [
                    Text(
                      format.integer(steps),
                      style: numberStyle(
                        theme.textTheme.displaySmall,
                        color: colors.activity,
                      ),
                    ),
                    CaptionText(l10n.widgetSubStepsGoal(goal)),
                  ],
                ),
              ),
              Text(
                format.percent(view.goalShare * 100),
                style: numberStyle(
                  theme.textTheme.titleSmall,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProgressBar(
            value: view.goalShare,
            color: colors.activity,
            height: 8,
            semanticsLabel: l10n.todayStepsSemantics(
              format.integer(steps),
              goal,
            ),
          ),
          if (view.today == null) ...[
            const SizedBox(height: 12),
            BodyText(l10n.activityNoStepsToday),
          ],
          const SizedBox(height: 16),
          HourlyStepsChart(
            key: ActivityKeys.hourly,
            steps: view.hourlySteps,
            color: colors.activity,
            semanticsLabel: peak == null
                ? l10n.activityHourlyEmptySemantics
                : l10n.activityHourlySemantics(
                    _hourLabel(format, peak.hour),
                    format.integer(peak.steps),
                  ),
          ),
          const SizedBox(height: 6),
          TimeAxis(
            labels: [
              for (final hour in const [0, 6, 12, 18, 23])
                _hourLabel(format, hour),
            ],
          ),
        ],
      ),
    );
  }

  static String _hourLabel(MetricFormat format, int hour) =>
      format.clock(DateTime.utc(2000, 1, 1, hour), Duration.zero);
}

class _Tile extends StatelessWidget {
  const new({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MetricCard(
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptionText(label),
            const SizedBox(height: 4),
            Text(
              value,
              style: numberStyle(Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const new({required this.view});

  final ActivityDayView view;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final counted = [
      for (final day in view.week)
        if (day.activity case final activity?) activity.steps,
    ];
    return MetricCard(
      key: ActivityKeys.week,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: l10n.activityWeekTitle, accent: colors.activity),
          if (counted.isNotEmpty) ...[
            const SizedBox(height: 4),
            CaptionText(
              l10n.activityWeekAverage(
                format.integer(
                  counted.reduce((a, b) => a + b) / counted.length,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (var i = 0; i < view.week.length; i++)
            _WeekRow(
              key: ActivityKeys.day(i),
              day: view.week[i],
              goal: view.stepGoal,
            ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const new({required this.day, required this.goal, super.key});

  final ActivityWeekDay day;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final activity = day.activity;
    final date = format.date(day.date);
    final semantics = activity == null
        ? l10n.activityDayNoDataSemantics(date)
        : l10n.activityDaySemantics(
            date,
            format.integer(activity.steps),
            format.integer(goal),
          );
    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MetricRow(
              label: format.weekday(day.date),
              value: activity == null
                  ? l10n.activityDayNoData
                  : l10n.activityDaySteps(format.integer(activity.steps)),
              valueColor: activity == null ? colors.textLabel : null,
            ),
            const SizedBox(height: 6),
            ProgressBar(
              value: activity == null || goal <= 0 ? 0 : activity.steps / goal,
              color: colors.activity,
            ),
          ],
        ),
      ),
    );
  }
}
