import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/presentation/sync_status_banner.dart';
import 'package:open_ring/features/today/application/readiness_view.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/today/presentation/readiness_verdict.dart';
import 'package:open_ring/features/today/presentation/today_cards.dart';
import 'package:open_ring/features/workout/presentation/workout_entry_button.dart';

class TodayScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    return AppPage(
      title: format.l10n.tabToday,
      subtitle: format.date(ref.watch(currentDateProvider)),
      titleTrailing: const _TodaySyncChip(),
      onRefresh: () => ref.read(todaySyncAttemptProvider.notifier).sync(),
      children: [
        const _TodaySyncBanner(),
        AsyncBody(
          value: ref.watch(todayViewProvider),
          builder: (view) => _TodayBody(view: view),
        ),
      ],
    );
  }
}

class _TodaySyncChip extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(todayViewProvider).value;
    if (view == null) return const SizedBox.shrink();
    return SyncChip(view: view);
  }
}

class _TodaySyncBanner extends ConsumerWidget {
  const new();

  // While the offline card is up it reports the failed attempt itself.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stale =
        ref.watch(todayViewProvider).value?.freshness == SyncFreshness.stale;
    final syncing = ref.watch(ringSyncProvider.select((s) => s.syncing));
    if (stale && !syncing) return const SizedBox.shrink();
    return const SyncStatusBanner();
  }
}

class _TodayBody extends StatelessWidget {
  const new({required this.view});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    final freshness = view.freshness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...switch (freshness) {
          SyncFreshness.unpaired => [
            EmptyStateCard(
              icon: Icons.radio_button_unchecked_rounded,
              accent: colors.oxygen,
              message: l10n.todayEmpty,
              actionLabel: l10n.todayPairAction,
              actionKey: TodayKeys.pairAction,
              onAction: () => context.go(AppTab.ring.path),
            ),
          ],
          SyncFreshness.neverSynced => [
            EmptyStateCard(
              icon: Icons.sync_rounded,
              accent: colors.oxygen,
              message: l10n.todayFirstSync,
              actionLabel: l10n.metricOpenRing,
              actionKey: TodayKeys.pairAction,
              onAction: () => context.go(AppTab.ring.path),
            ),
          ],
          SyncFreshness.fresh || SyncFreshness.stale => [
            if (freshness == SyncFreshness.stale) ...[
              OfflineCard(key: TodayKeys.offline, view: view),
              const SizedBox(height: cardGap),
            ],
            _ReadinessCard(
              readiness: view.readiness,
              staleSyncAt: freshness == SyncFreshness.stale
                  ? view.ring.lastSyncAt
                  : null,
            ),
            const SizedBox(height: cardGap),
            SleepSummaryCard(view: view),
            const SizedBox(height: cardGap),
            SummaryColumns(view: view),
            const SizedBox(height: cardGap),
            const WorkoutEntryButton(),
            if (freshness == SyncFreshness.stale) ...[
              const SizedBox(height: 8),
              CaptionText(
                key: TodayKeys.workoutNote,
                l10n.todayWorkoutNeedsRing,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            const EstimateNote(),
          ],
        },
      ],
    );
  }
}

// A sync right after the last sleep span may have cut the night short.
const _nightSettledAfter = Duration(minutes: 30);

class _ReadinessCard extends StatelessWidget {
  const new({required this.readiness, required this.staleSyncAt});

  final ReadinessView readiness;
  final DateTime? staleSyncAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final value = readiness.value;
    final rhr = readiness.restingHeartRate;
    final hrv = readiness.hrv;
    final sleep = readiness.sleep.scoreValue;
    final load = readiness.activityLoad;
    final ring = ScoreRing(
      value: value,
      color: colors.textPrimary,
      caption: l10n.readinessOf100,
      semanticsLabel: value == null
          ? l10n.readinessPendingSemantics
          : l10n.readinessSemantics(value),
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            value == null ? l10n.readinessTitle : readinessVerdict(l10n, value),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 4),
        CaptionText(_footer(format)),
      ],
    );
    return MetricCard(
      key: TodayKeys.readiness,
      padding: const EdgeInsets.all(18),
      onTap: () => context.go(AppPaths.readiness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (context.prefersSingleColumn) ...[
            Align(alignment: AlignmentDirectional.centerStart, child: ring),
            const SizedBox(height: 12),
            heading,
          ],
          if (!context.prefersSingleColumn)
            Row(
              children: [
                SizedBox(width: 112, child: ring),
                const SizedBox(width: 18),
                Expanded(child: heading),
              ],
            ),
          const SizedBox(height: 14),
          MetricRow(
            label: l10n.readinessFactorRestingHr,
            value: _value(format, rhr.today, format.bpm),
            delta: _delta(format, rhr.deviation?.delta),
            deltaColor: _deltaColor(
              colors,
              rhr.deviation?.delta,
              higherIsBetter: false,
            ),
          ),
          const SizedBox(height: 6),
          MetricRow(
            label: l10n.readinessFactorHrv,
            value: _value(format, hrv.today, format.ms),
            delta: _delta(format, hrv.deviation?.delta),
            deltaColor: _deltaColor(
              colors,
              hrv.deviation?.delta,
              higherIsBetter: true,
            ),
          ),
          const SizedBox(height: 6),
          MetricRow(
            label: l10n.tabSleep,
            value: sleep == null ? l10n.metricNoReading : '$sleep',
          ),
          if (load != null) ...[
            const SizedBox(height: 6),
            MetricRow(
              label: l10n.readinessFactorLoad,
              value: format.decimal(load.ratio, digits: 2),
            ),
          ],
        ],
      ),
    );
  }

  bool get _nightComplete {
    final synced = staleSyncAt;
    final night = readiness.sleep.night;
    if (synced == null || night == null || readiness.value == null) {
      return false;
    }
    return synced.difference(night.end) >= _nightSettledAfter;
  }

  String _footer(MetricFormat format) {
    final nights = readiness.baselineNights;
    final building = readiness.building;
    if (_nightComplete) return format.l10n.todayReadinessNightComplete;
    if (readiness.value != null && nights != null) {
      return format.l10n.todayReadinessCompared(nights);
    }
    if (building != null) {
      return format.l10n.metricBaselineBuilding(
        building.daysCollected,
        building.daysNeeded,
      );
    }
    return format.l10n.todayReadinessPending;
  }

  String _value(
    MetricFormat format,
    double? value,
    String Function(double) show,
  ) => value == null ? format.l10n.metricNoReading : show(value);

  String? _delta(MetricFormat format, double? delta) =>
      delta == null ? null : format.signed(delta);

  Color? _deltaColor(
    AppColors colors,
    double? delta, {
    required bool higherIsBetter,
  }) {
    if (delta == null || delta.round() == 0) return colors.textLabel;
    return (delta > 0) == higherIsBetter ? colors.activity : colors.stress;
  }
}
