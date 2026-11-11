import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/presentation/sync_labels.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/sleep/presentation/sleep_labels.dart';
import 'package:open_ring/features/sleep/presentation/sleep_stage_summary.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/application/today_view.dart';

abstract final class TodayKeys {
  static const syncChip = Key('today_sync_chip');
  static const offline = Key('today_offline');
  static const pairAction = Key('today_pair_action');
  static const offlineAction = Key('today_offline_action');
  static const offlineHelp = Key('today_offline_help');
  static const offlineTried = Key('today_offline_tried');
  static const workoutNote = Key('today_workout_note');
  static const readiness = Key('today_readiness');
  static const sleep = Key('today_sleep');
  static const activity = Key('today_activity');
  static const heart = Key('today_heart');
  static const staleMarker = Key('today_stale_marker');
}

String lastSyncLabel(MetricFormat format, TodayView view) =>
    format.clockOrDay(view.ring.lastSyncAt!, view.now);

class SyncChip extends StatelessWidget {
  const new({required this.view, super.key});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final battery = view.ring.batteryPercent;
    final (dot, text) = switch (view.freshness) {
      SyncFreshness.unpaired => (colors.textLabel, l10n.todayNoRing),
      SyncFreshness.neverSynced => (colors.textLabel, l10n.todayNeverSynced),
      SyncFreshness.stale => (
        colors.textLabel,
        l10n.todayNotSyncedFor(
          view.now.difference(view.ring.lastSyncAt!).inHours,
        ),
      ),
      SyncFreshness.fresh => (
        colors.activity,
        battery == null
            ? l10n.todaySynced(lastSyncLabel(format, view))
            : l10n.todaySyncedBattery(lastSyncLabel(format, view), battery),
      ),
    };
    return Material(
      color: colors.surface,
      shape: StadiumBorder(side: BorderSide(color: colors.surfaceBorder)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: TodayKeys.syncChip,
        onTap: () => context.go(AppTab.ring.path),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Flexible(child: CaptionText(text, color: colors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OfflineCard extends ConsumerWidget {
  const new({required this.view, super.key});

  final TodayView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final since = lastSyncLabel(format, view);
    final battery = view.ring.batteryPercent;
    final sync = ref.watch(ringSyncProvider);
    final error = sync.syncing ? null : sync.lastError;
    final attempt = ref.watch(todaySyncAttemptProvider);
    final primary = ActionButton(
      key: TodayKeys.offlineAction,
      label: error == null ? l10n.todaySyncNow : l10n.syncRetry,
      onPressed: sync.syncing
          ? null
          : () => unawaited(ref.read(todaySyncAttemptProvider.notifier).sync()),
    );
    final help = SecondaryButton(
      key: TodayKeys.offlineHelp,
      label: l10n.todayOfflineWhatToDo,
      onPressed: () => context.go(AppTab.ring.path),
    );
    return Semantics(
      liveRegion: true,
      child: MetricCard(
        color: colors.surfaceInner,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.bluetooth_disabled_rounded,
                  size: 28,
                  color: colors.textPrimary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.todayOfflineTitle(since),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BodyText(
              battery == null
                  ? l10n.todayOfflineReason
                  : '${l10n.todayOfflineReason} ${l10n.todayOfflineBattery(battery)}',
            ),
            const SizedBox(height: 8),
            BodyText(l10n.todayOfflineHistory(since)),
            if (error != null) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                key: TodayKeys.offlineTried,
                decoration: BoxDecoration(
                  color: colors.track,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: BodyText(_tried(format, error, attempt)),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (context.prefersSingleColumn) ...[
              primary,
              const SizedBox(height: 10),
              help,
            ],
            if (!context.prefersSingleColumn)
              Row(
                children: [
                  Expanded(child: primary),
                  const SizedBox(width: 10),
                  Expanded(child: help),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _tried(MetricFormat format, SyncError error, DateTime? attempt) {
    final reason = error.message(format.l10n);
    if (attempt == null) return reason;
    return format.l10n.todayOfflineTried(
      format.clockOrDay(attempt, view.now),
      reason,
    );
  }
}

class StaleMarker extends StatelessWidget {
  const new({required this.view, super.key});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    return Row(
      key: TodayKeys.staleMarker,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_rounded, size: 14, color: colors.textLabel),
        const SizedBox(width: 4),
        Flexible(
          child: CaptionText(
            format.l10n.metricDataUntil(lastSyncLabel(format, view)),
          ),
        ),
      ],
    );
  }
}

class SleepSummaryCard extends StatelessWidget {
  const new({required this.view, super.key});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final day = view.lastNight;
    final night = day.night;
    final score = day.scoreValue;
    return MetricCard(
      key: TodayKeys.sleep,
      onTap: () => context.go(AppTab.sleep.path),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              AccentTitle(title: l10n.tabSleep, accent: colors.sleep),
              if (night != null) CaptionText(nightRange(format, night)),
            ],
          ),
          const SizedBox(height: 8),
          if (night == null) BodyText(l10n.sleepEmpty),
          if (night != null) ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 10,
              runSpacing: 2,
              children: [
                Text(
                  format.duration(night.asleep),
                  style: numberStyle(theme.textTheme.headlineMedium),
                ),
                Text(
                  score == null
                      ? l10n.sleepScoreNone
                      : l10n.todaySleepScore(score),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.sleep,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SleepStageBar(night: night, remMeasured: view.remMeasured),
            const SizedBox(height: 8),
            SleepStageLegend(night: night, remMeasured: view.remMeasured),
          ],
        ],
      ),
    );
  }
}

class ActivitySummaryCard extends ConsumerWidget {
  const new({required this.view, super.key});

  final TodayView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final units = UnitFormat.of(context, ref);
    final format = units.format;
    final l10n = format.l10n;
    final activity = view.activity;
    return MetricCard(
      key: TodayKeys.activity,
      onTap: () => context.go(AppTab.activity.path),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: l10n.tabActivity, accent: colors.activity),
          const SizedBox(height: 10),
          if (activity == null) BodyText(l10n.todayActivityEmpty),
          if (activity != null) ...[
            Text(
              format.integer(activity.steps),
              style: numberStyle(theme.textTheme.headlineMedium),
            ),
            CaptionText(l10n.todayStepsOfGoal(format.integer(view.stepGoal))),
            const SizedBox(height: 10),
            ProgressBar(
              value: activity.steps / view.stepGoal,
              color: colors.activity,
              semanticsLabel: l10n.todayStepsSemantics(
                format.integer(activity.steps),
                format.integer(view.stepGoal),
              ),
            ),
            const SizedBox(height: 8),
            CaptionText(
              units.select(
                l10n.todayActivityDetail,
                l10n.todayActivityDetailMi,
              )(
                format.integer(activity.activeKilocalories),
                units.distance(activity.distanceMeters),
              ),
            ),
          ],
          if (view.freshness == SyncFreshness.stale) ...[
            const SizedBox(height: 10),
            StaleMarker(view: view),
          ],
        ],
      ),
    );
  }
}

class HeartSummaryCard extends StatelessWidget {
  const new({required this.view, super.key});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final heart = view.heart;
    final average = heart.heartRate.mean;
    final spo2 = heart.spo2Night?.mean ?? heart.spo2.mean;
    final stress = heart.stressSummary?.mean;
    final hrv = heart.baselines.hrv.today;
    return MetricCard(
      key: TodayKeys.heart,
      onTap: () => context.go(AppTab.heart.path),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: l10n.tabHeart, accent: colors.heart),
          const SizedBox(height: 10),
          if (heart.isEmpty) BodyText(l10n.todayHeartEmpty),
          if (average != null)
            MergeSemantics(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 4,
                children: [
                  Text(
                    format.integer(average),
                    style: numberStyle(theme.textTheme.headlineMedium),
                  ),
                  CaptionText(l10n.heartAverageBpm),
                ],
              ),
            ),
          if (!heart.isEmpty) const SizedBox(height: 10),
          if (spo2 != null)
            MetricRow(
              label: l10n.heartMetricSpo2,
              value: format.percent(spo2),
              valueColor: colors.oxygen,
            ),
          if (stress != null)
            MetricRow(
              label: l10n.heartMetricStress,
              value: format.integer(stress),
              valueColor: colors.stress,
            ),
          if (hrv != null)
            MetricRow(label: l10n.heartMetricHrv, value: format.ms(hrv)),
          if (view.freshness == SyncFreshness.stale) ...[
            const SizedBox(height: 10),
            StaleMarker(view: view),
          ],
        ],
      ),
    );
  }
}

class SummaryColumns extends StatelessWidget {
  const new({required this.view, super.key});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    return AdaptiveColumns(
      first: ActivitySummaryCard(view: view),
      second: HeartSummaryCard(view: view),
    );
  }
}
