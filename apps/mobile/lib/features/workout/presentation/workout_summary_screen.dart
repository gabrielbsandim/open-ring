import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/application/workout_state.dart';
import 'package:open_ring/features/workout/domain/workout_analysis.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/presentation/route_map.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/features/workout/presentation/workout_widgets.dart';

const maxHeartRateBars = 30;
const _slowestSplitShare = 0.45;

abstract final class WorkoutSummaryKeys {
  static const duration = Key('summary_duration');
  static const distance = Key('summary_distance');
  static const route = Key('summary_route');
  static const noRoute = Key('summary_no_route');
  static const stats = Key('summary_stats');
  static const climb = Key('summary_climb');
  static const splits = Key('summary_splits');
  static const heart = Key('summary_heart');
  static const zones = Key('summary_zones');
  static const pauses = Key('summary_pauses');
  static const status = Key('summary_status');
  static const retry = Key('summary_retry');
  static const exportGpx = Key('summary_export_gpx');
  static const exportCsv = Key('summary_export_csv');
  static const exportFailed = Key('summary_export_failed');
  static const delete = Key('summary_delete');
  static const deleteConfirm = Key('summary_delete_confirm');
  static const deleteCancel = Key('summary_delete_cancel');
  static const deleteFailed = Key('summary_delete_failed');
  static const deleted = Key('summary_deleted');
  static const none = Key('summary_none');
  static const back = Key('summary_back');

  static Key split(int number) => Key('summary_split_$number');
}

typedef HeartRateBars = ({List<double?> values, int minutesPerBar});

HeartRateBars heartRateBars(
  FinishedWorkout workout, {
  int maxBars = maxHeartRateBars,
}) {
  final minutes = math.max(
    1,
    (workout.end.difference(workout.start).inSeconds / 60).ceil(),
  );
  final perBar = math.max(1, (minutes / maxBars).ceil());
  final count = (minutes / perBar).ceil();
  final sums = List<int>.filled(count, 0);
  final counts = List<int>.filled(count, 0);
  for (final sample in workout.heartRate) {
    final offset = sample.at.difference(workout.start).inSeconds;
    final index = (offset ~/ (perBar * 60)).clamp(0, count - 1);
    sums[index] += sample.bpm;
    counts[index]++;
  }
  return (
    values: [for (var i = 0; i < count; i++) _mean(sums[i], counts[i])],
    minutesPerBar: perBar,
  );
}

double? _mean(int sum, int count) => count == 0 ? null : sum / count;

double? averageAccuracy(WorkoutRoute route) {
  final known = [for (final point in route.points) ?point.accuracyMeters];
  if (known.isEmpty) return null;
  return known.reduce((a, b) => a + b) / known.length;
}

class WorkoutSummaryScreen extends ConsumerStatefulWidget {
  const new({this.workoutId, super.key});

  final int? workoutId;

  @override
  ConsumerState<WorkoutSummaryScreen> createState() =>
      _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends ConsumerState<WorkoutSummaryScreen> {
  bool _deleted = false;

  @override
  Widget build(BuildContext context) {
    final l10n = MetricFormat.of(context).l10n;
    if (_deleted) {
      return AppPage(
        title: l10n.workoutSummaryTitle,
        children: const [_DeletedCard()],
      );
    }
    final id = widget.workoutId;
    if (id != null) return _savedSummary(id);
    return _latestSummary();
  }

  void _onDeleted() => setState(() => _deleted = true);

  Widget _latestSummary() {
    final state = ref.watch(workoutProvider);
    final controller = ref.read(workoutProvider.notifier);
    final session = controller.session;
    if (session == null || session.status != WorkoutStatus.finished) {
      return const _NoneView();
    }
    final workout = session.finished();
    final saved = state.save == WorkoutSave.saved ? state.workoutId : null;
    return _Summary(
      workout: workout,
      zones: session.profile.zones,
      offset: workout.start.toLocal().timeZoneOffset,
      workoutId: saved,
      onDeleted: _onDeleted,
      status: _SaveStatusCard(
        workout: workout,
        state: state,
        onRetry: controller.saveAgain,
      ),
    );
  }

  Widget _savedSummary(int id) {
    final l10n = MetricFormat.of(context).l10n;
    final zones = ref.watch(savedWorkoutZonesProvider);
    final value = ref.watch(savedWorkoutProvider(id));
    if (!value.hasValue) {
      return AppPage(
        title: l10n.workoutSummaryTitle,
        children: [
          AsyncBody(value: value, builder: (_) => const SizedBox.shrink()),
        ],
      );
    }
    final saved = value.requireValue;
    if (saved == null) return const _NoneView(missing: true);
    return _Summary(
      workout: saved.workout,
      zones: zones,
      offset: saved.utcOffset,
      workoutId: saved.id,
      onDeleted: _onDeleted,
      status: _HealthCard(saved: saved),
    );
  }
}

class _NoneView extends StatelessWidget {
  const new({this.missing = false});

  final bool missing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return AppPage(
      title: l10n.workoutSummaryTitle,
      children: [
        EmptyStateCard(
          key: WorkoutSummaryKeys.none,
          icon: Icons.directions_run_rounded,
          accent: colors.activity,
          message: missing
              ? l10n.workoutSummaryMissing
              : l10n.workoutSummaryNone,
          actionLabel: l10n.workoutChoose,
          onAction: () => context.go(AppPaths.workout),
        ),
      ],
    );
  }
}

class _DeletedCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NoticeCard(
          key: WorkoutSummaryKeys.deleted,
          icon: Icons.delete_outline_rounded,
          accent: colors.textSecondary,
          title: l10n.workoutDeletedTitle,
          body: l10n.workoutDeletedBody(workoutHealthPlatform()),
        ),
        const SizedBox(height: 20),
        SecondaryButton(
          key: WorkoutSummaryKeys.back,
          label: l10n.workoutBackToActivity,
          onPressed: () => context.go(AppTab.activity.path),
        ),
      ],
    );
  }
}

class _Summary extends ConsumerWidget {
  const new({
    required this.workout,
    required this.zones,
    required this.offset,
    required this.status,
    required this.workoutId,
    required this.onDeleted,
  });

  final FinishedWorkout workout;
  final HeartRateZones? zones;
  final Duration offset;
  final Widget status;
  final int? workoutId;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = UnitFormat.of(context, ref);
    final format = units.format;
    final l10n = format.l10n;
    final date = LocalDate.fromInstant(workout.start, offset);
    final zoneTable = zones;
    final splits = workout.gps
        ? units.splitsOf(workout)
        : const <WorkoutSplit>[];
    return AppPage(
      title: workout.type.label(l10n),
      subtitle: l10n.workoutSummaryWhen(
        format.date(date),
        format.clock(workout.start, offset),
        format.clock(workout.end, offset),
      ),
      children: [
        _Headline(workout: workout, units: units),
        const SizedBox(height: 16),
        if (workout.gps) ...[
          _RouteCard(workout: workout, offset: offset, units: units),
          const SizedBox(height: cardGap),
        ],
        _Stats(workout: workout, units: units),
        const SizedBox(height: 8),
        CaptionText(
          workout.gps ? l10n.workoutSummaryNote : l10n.workoutSummaryNoteIndoor,
        ),
        if (splits.isNotEmpty) ...[
          const SizedBox(height: cardGap),
          _SplitsCard(splits: splits, units: units),
        ],
        const SizedBox(height: cardGap),
        _HeartCard(workout: workout, offset: offset),
        if (zoneTable != null && workout.heartRate.isNotEmpty) ...[
          const SizedBox(height: cardGap),
          _ZonesCard(workout: workout, zones: zoneTable),
        ],
        const SizedBox(height: cardGap),
        _PausesCard(pauses: workout.pauses, offset: offset),
        const SizedBox(height: cardGap),
        status,
        const SizedBox(height: 20),
        _Actions(
          workout: workout,
          offset: offset,
          workoutId: workoutId,
          onDeleted: onDeleted,
        ),
        SecondaryButton(
          key: WorkoutSummaryKeys.back,
          label: l10n.workoutBackToActivity,
          onPressed: () => context.go(AppTab.activity.path),
        ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const new({required this.workout, required this.units});

  final FinishedWorkout workout;
  final UnitFormat units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = units.format;
    final l10n = format.l10n;
    final distance = workout.distanceMeters;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 16,
      runSpacing: 8,
      children: [
        MergeSemantics(
          key: WorkoutSummaryKeys.duration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CaptionText(l10n.workoutDuration),
              Text(
                format.elapsedClock(workout.elapsed),
                style: numberStyle(theme.textTheme.displaySmall),
              ),
            ],
          ),
        ),
        if (distance != null)
          MergeSemantics(
            key: WorkoutSummaryKeys.distance,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CaptionText(l10n.workoutDistanceGps),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 6,
                  children: [
                    Text(
                      units.distance(distance),
                      style: numberStyle(
                        theme.textTheme.headlineMedium,
                        color: colors.activity,
                      ),
                    ),
                    CaptionText(units.distanceUnit),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const new({required this.workout, required this.offset, required this.units});

  final FinishedWorkout workout;
  final Duration offset;
  final UnitFormat units;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = units.format;
    final l10n = format.l10n;
    final route = workout.route;
    if (route.isEmpty) {
      return EmptyStateCard(
        key: WorkoutSummaryKeys.noRoute,
        icon: Icons.location_off_outlined,
        accent: colors.textLabel,
        message: l10n.workoutRouteNone,
      );
    }
    final accuracy = averageAccuracy(route);
    return MetricCard(
      key: WorkoutSummaryKeys.route,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                AccentTitle(
                  title: l10n.workoutRouteTitle,
                  accent: colors.activity,
                ),
                if (accuracy != null)
                  CaptionText(units.routeAccuracy(accuracy)),
              ],
            ),
          ),
          RouteMap(
            segments: route.segments,
            semanticsLabel: units.routeSemantics(workout.distanceMeters),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _Legend(
                  marker: _StartMarker(color: colors.activity),
                  text: l10n.workoutRouteStart(
                    format.clock(workout.start, offset),
                  ),
                ),
                _Legend(
                  marker: _EndMarker(color: colors.textPrimary),
                  text: l10n.workoutRouteEnd(format.clock(workout.end, offset)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const new({required this.marker, required this.text});

  final Widget marker;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      marker,
      const SizedBox(width: 6),
      Flexible(child: CaptionText(text)),
    ],
  );
}

class _StartMarker extends StatelessWidget {
  const new({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 2),
    ),
  );
}

class _EndMarker extends StatelessWidget {
  const new({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class _Stats extends StatelessWidget {
  const new({required this.workout, required this.units});

  final FinishedWorkout workout;
  final UnitFormat units;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = units.format;
    final l10n = format.l10n;
    final type = workout.type;
    final distance = workout.distanceMeters;
    final climb = workout.gps ? elevationGainMeters(workout.route) : null;
    final pace = distance == null || distance < minPaceDistanceMeters
        ? null
        : Duration(
            microseconds: (workout.elapsed.inMicroseconds * 1000 / distance)
                .round(),
          );
    return WorkoutGrid(
      key: WorkoutSummaryKeys.stats,
      children: [
        if (workout.gps)
          WorkoutMetricTile(
            label: type.showsSpeed
                ? l10n.workoutAverageSpeed
                : l10n.workoutAveragePace,
            value: units.paceOrSpeed(type, pace),
            unit: units.paceOrSpeedUnit(type),
          ),
        WorkoutMetricTile(
          label: l10n.workoutAverageHeartRate,
          value: format.optionalInteger(workout.averageHeartRate),
          unit: l10n.workoutUnitBpm,
          valueColor: colors.heart,
        ),
        WorkoutMetricTile(
          label: l10n.workoutMaxHeartRate,
          value: format.optionalInteger(workout.maxHeartRate),
          unit: l10n.workoutUnitBpm,
          valueColor: colors.heart,
        ),
        WorkoutMetricTile(
          label: l10n.workoutEnergy,
          value: format.optionalInteger(workout.activeKilocalories),
          unit: l10n.workoutUnitKcal,
        ),
        if (climb != null)
          WorkoutMetricTile(
            key: WorkoutSummaryKeys.climb,
            label: l10n.workoutElevationGain,
            value: units.length(climb),
            unit: units.lengthUnit,
          ),
      ],
    );
  }
}

class _HeartCard extends StatelessWidget {
  const new({required this.workout, required this.offset});

  final FinishedWorkout workout;
  final Duration offset;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final average = workout.averageHeartRate;
    final samples = workout.heartRate;
    final bars = heartRateBars(workout);
    final middle = workout.start.add(
      workout.end.difference(workout.start) ~/ 2,
    );
    return MetricCard(
      key: WorkoutSummaryKeys.heart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              AccentTitle(title: l10n.workoutHeartTitle, accent: colors.heart),
              if (samples.isNotEmpty)
                CaptionText(l10n.workoutHeartBars(bars.minutesPerBar)),
            ],
          ),
          const SizedBox(height: 12),
          if (samples.isEmpty || average == null)
            BodyText(l10n.workoutHeartNone),
          if (samples.isNotEmpty && average != null) ...[
            HourlyBars(
              values: bars.values,
              color: colors.heart,
              semanticsLabel: l10n.workoutHeartSemantics(
                format.integer(samples.map((s) => s.bpm).reduce(math.min)),
                format.integer(workout.maxHeartRate ?? average),
                format.integer(average),
              ),
            ),
            const SizedBox(height: 6),
            TimeAxis(
              labels: [
                format.clock(workout.start, offset),
                format.clock(middle, offset),
                format.clock(workout.end, offset),
              ],
            ),
            const SizedBox(height: 8),
            CaptionText(l10n.workoutHeartAverage(format.integer(average))),
          ],
        ],
      ),
    );
  }
}

class _ZonesCard extends StatelessWidget {
  const new({required this.workout, required this.zones});

  final FinishedWorkout workout;
  final HeartRateZones zones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final times = zones.timeInZones(workout.heartRate);
    final longest = times.values.fold(Duration.zero, (a, b) => a > b ? a : b);
    return MetricCard(
      key: WorkoutSummaryKeys.zones,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              AccentTitle(title: l10n.workoutZonesTitle, accent: colors.heart),
              CaptionText(
                l10n.workoutZonesMax(format.integer(zones.maxHeartRate)),
              ),
            ],
          ),
          for (final zone in zones.zones) ...[
            const SizedBox(height: 12),
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MetricRow(
                    label: l10n.workoutZoneName(
                      zone.number,
                      zoneName(l10n, zone.number),
                    ),
                    value: format.duration(times[zone.number] ?? Duration.zero),
                  ),
                  CaptionText(_range(format, zone)),
                  const SizedBox(height: 6),
                  ProgressBar(
                    value: longest == Duration.zero
                        ? 0
                        : (times[zone.number] ?? Duration.zero).inSeconds /
                              longest.inSeconds,
                    color: colors.heart,
                    height: 8,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            l10n.workoutZonesNote,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textLabel),
          ),
        ],
      ),
    );
  }

  static String _range(MetricFormat format, HeartRateZone zone) {
    final upper = zone.upperBpm;
    final lower = format.integer(zone.lowerBpm);
    if (upper == null) return format.l10n.workoutZoneFrom(lower);
    return format.l10n.workoutZoneRange(lower, format.integer(upper - 1));
  }
}

class _SaveStatusCard extends StatelessWidget {
  const new({
    required this.workout,
    required this.state,
    required this.onRetry,
  });

  final FinishedWorkout workout;
  final WorkoutState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return switch (state.save) {
      WorkoutSave.saved => NoticeCard(
        key: WorkoutSummaryKeys.status,
        icon: Icons.check_circle_outline_rounded,
        accent: colors.activity,
        border: colors.activity,
        title: l10n.workoutSummarySaved,
        body: l10n.workoutSummarySavedBody(
          workout.heartRate.length,
          workoutHealthPlatform(),
        ),
      ),
      WorkoutSave.failed => NoticeCard(
        key: WorkoutSummaryKeys.status,
        icon: Icons.error_outline_rounded,
        accent: colors.heart,
        title: l10n.workoutSaveFailedTitle,
        body: l10n.workoutSaveFailedBody,
        actions: [
          ActionButton(
            key: WorkoutSummaryKeys.retry,
            label: l10n.workoutSaveRetry,
            onPressed: () => unawaited(onRetry()),
          ),
        ],
      ),
      WorkoutSave.none || WorkoutSave.saving => NoticeCard(
        key: WorkoutSummaryKeys.status,
        icon: Icons.save_outlined,
        accent: colors.textSecondary,
        title: l10n.workoutSavingTitle,
      ),
    };
  }
}

class _HealthCard extends StatelessWidget {
  const new({required this.saved});

  final SavedWorkout saved;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final health = saved.health;
    final samples = saved.workout.heartRate.length;
    final formatted = format.integer(samples);
    final body = switch (health) {
      WorkoutHealthStatus.sent when saved.workout.route.isEmpty =>
        l10n.workoutSummarySentNoRoute(samples, formatted),
      WorkoutHealthStatus.sent => l10n.workoutSummarySentRoute(
        samples,
        formatted,
      ),
      WorkoutHealthStatus.failed => null,
      WorkoutHealthStatus.pending || WorkoutHealthStatus.notQueued =>
        l10n.workoutSummarySavedBody(samples, workoutHealthPlatform()),
    };
    return NoticeCard(
      key: WorkoutSummaryKeys.status,
      icon: switch (health) {
        WorkoutHealthStatus.sent => Icons.check_circle_outline_rounded,
        WorkoutHealthStatus.failed => Icons.error_outline_rounded,
        WorkoutHealthStatus.pending ||
        WorkoutHealthStatus.notQueued => Icons.schedule_rounded,
      },
      accent: health.color(colors),
      title: health.label(l10n),
      body: body,
    );
  }
}

class _SplitsCard extends StatelessWidget {
  const new({required this.splits, required this.units});

  final List<WorkoutSplit> splits;
  final UnitFormat units;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = units.l10n;
    final paces = [for (final split in splits) split.pace.inMicroseconds];
    final fastest = paces.reduce(math.min);
    final slowest = paces.reduce(math.max);
    final last = splits.last;
    return MetricCard(
      key: WorkoutSummaryKeys.splits,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              AccentTitle(title: units.splitsTitle, accent: colors.activity),
              CaptionText(l10n.workoutSplitsHint),
            ],
          ),
          for (final split in splits) ...[
            const SizedBox(height: 10),
            _SplitRow(
              key: WorkoutSummaryKeys.split(split.number),
              split: split,
              units: units,
              share: slowest == fastest
                  ? 1
                  : 1 -
                        (split.pace.inMicroseconds - fastest) /
                            (slowest - fastest) *
                            _slowestSplitShare,
            ),
          ],
          if (last.partial) ...[
            const SizedBox(height: 12),
            CaptionText(units.splitLastNote(last)),
          ],
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const new({
    required this.split,
    required this.units,
    required this.share,
    super.key,
  });

  final WorkoutSplit split;
  final UnitFormat units;
  final double share;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = units.format;
    final l10n = format.l10n;
    final pace = '${units.pace(split.pace)} ${units.paceUnit}';
    final bpm = split.averageHeartRate;
    final value = bpm == null
        ? pace
        : '$pace · ${format.integer(bpm)} ${l10n.workoutUnitBpm}';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: units.splitSemantics(split),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetricRow(
            label: '${units.splitLabel} ${units.splitNumber(split)}',
            value: value,
          ),
          const SizedBox(height: 4),
          ProgressBar(value: share, color: colors.activity),
        ],
      ),
    );
  }
}

class _PausesCard extends StatelessWidget {
  const new({required this.pauses, required this.offset});

  final List<WorkoutPause> pauses;
  final Duration offset;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return MetricCard(
      key: WorkoutSummaryKeys.pauses,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: l10n.workoutPausesTitle, accent: colors.textLabel),
          const SizedBox(height: 8),
          if (pauses.isEmpty) BodyText(l10n.workoutPausesNone),
          if (pauses.isNotEmpty) ...[
            BodyText(
              l10n.workoutPausesBody(
                pauses.length,
                format.duration(pausedTime(pauses)),
              ),
            ),
            for (final pause in pauses) ...[
              const SizedBox(height: 6),
              MetricRow(
                label: l10n.workoutPauseRange(
                  format.clock(pause.start, offset),
                  format.clock(pause.end, offset),
                ),
                value: format.duration(pause.duration),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const new({
    required this.workout,
    required this.offset,
    required this.workoutId,
    required this.onDeleted,
  });

  final FinishedWorkout workout;
  final Duration offset;
  final int? workoutId;
  final VoidCallback onDeleted;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

enum _Busy { none, exporting, deleting }

class _ActionsState extends ConsumerState<_Actions> {
  _Busy _busy = _Busy.none;
  bool _confirming = false;
  bool _exportFailed = false;
  bool _deleteFailed = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    final id = widget.workoutId;
    final idle = _busy == _Busy.none;
    final children = <Widget>[
      ..._exportSection(idle: idle),
      if (id != null && !_confirming) ...[
        SecondaryButton(
          key: WorkoutSummaryKeys.delete,
          label: l10n.workoutDelete,
          color: colors.heart,
          onPressed: idle ? () => setState(() => _confirming = true) : null,
        ),
        const SizedBox(height: 12),
      ],
      if (id != null && _confirming) ...[
        NoticeCard(
          icon: Icons.delete_outline_rounded,
          accent: colors.heart,
          border: colors.heart,
          title: l10n.workoutDeleteTitle,
          body: l10n.workoutDeleteBody(workoutHealthPlatform()),
          actions: [
            SecondaryButton(
              key: WorkoutSummaryKeys.deleteCancel,
              label: l10n.workoutDeleteCancel,
              onPressed: idle
                  ? () => setState(() => _confirming = false)
                  : null,
            ),
            SecondaryButton(
              key: WorkoutSummaryKeys.deleteConfirm,
              label: l10n.workoutDeleteConfirm,
              color: colors.heart,
              onPressed: idle ? () => unawaited(_delete(id)) : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      if (_deleteFailed) ...[
        CaptionText(
          key: WorkoutSummaryKeys.deleteFailed,
          l10n.workoutDeleteFailed,
          color: colors.heart,
        ),
        const SizedBox(height: 12),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  List<Widget> _exportSection({required bool idle}) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    final hasRoute = !widget.workout.route.isEmpty;
    if (!hasRoute && widget.workout.heartRate.isEmpty) return const [];
    final csv = SecondaryButton(
      key: WorkoutSummaryKeys.exportCsv,
      label: l10n.workoutExportCsv,
      onPressed: idle ? () => unawaited(_export(_shareCsv)) : null,
    );
    return [
      if (hasRoute)
        ButtonPair(
          first: csv,
          second: SecondaryButton(
            key: WorkoutSummaryKeys.exportGpx,
            label: l10n.workoutExportGpx,
            onPressed: idle ? () => unawaited(_export(_shareGpx)) : null,
          ),
        ),
      if (!hasRoute) csv,
      if (_exportFailed) ...[
        const SizedBox(height: 6),
        CaptionText(
          key: WorkoutSummaryKeys.exportFailed,
          l10n.workoutExportFailed,
          color: colors.heart,
        ),
      ],
      const SizedBox(height: 12),
    ];
  }

  Future<void> _shareCsv() =>
      shareWorkoutCsv(ref, widget.workout, offset: widget.offset);

  Future<void> _shareGpx() => shareWorkoutGpx(ref, widget.workout);

  Future<void> _export(Future<void> Function() share) async {
    setState(() {
      _busy = _Busy.exporting;
      _exportFailed = false;
    });
    var failed = false;
    try {
      await share();
    } on Object {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _busy = _Busy.none;
      _exportFailed = failed;
    });
  }

  Future<void> _delete(int id) async {
    setState(() {
      _busy = _Busy.deleting;
      _deleteFailed = false;
    });
    var deleted = false;
    try {
      deleted = await deleteWorkout(ref, id);
    } on Object {
      deleted = false;
    }
    if (!mounted) return;
    if (deleted) {
      widget.onDeleted();
      return;
    }
    setState(() {
      _busy = _Busy.none;
      _confirming = false;
      _deleteFailed = true;
    });
  }
}
