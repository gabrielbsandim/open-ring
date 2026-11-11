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
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/workout/application/location_access_provider.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_state.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/presentation/route_map.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/features/workout/presentation/workout_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class LiveWorkoutKeys {
  static const link = Key('live_link');
  static const phase = Key('live_phase');
  static const clock = Key('live_clock');
  static const map = Key('live_map');
  static const gps = Key('live_gps');
  static const gpsProblem = Key('live_gps_problem');
  static const gpsRetry = Key('live_gps_retry');
  static const heart = Key('live_heart');
  static const zoneCaption = Key('live_zone_caption');
  static const reconnect = Key('live_reconnect');
  static const metrics = Key('live_metrics');
  static const toggle = Key('live_toggle');
  static const end = Key('live_end');
  static const confirm = Key('live_confirm');
  static const keepGoing = Key('live_keep_going');
  static const save = Key('live_save');
  static const discard = Key('live_discard');
  static const saving = Key('live_saving');
  static const saved = Key('live_saved');
  static const summary = Key('live_summary');
  static const failed = Key('live_failed');
  static const retry = Key('live_retry');
  static const discarded = Key('live_discarded');
  static const none = Key('live_none');
  static const settings = Key('live_settings');
}

class LiveWorkoutScreen extends ConsumerStatefulWidget {
  const new({this.initialConfirming = false, super.key});

  final bool initialConfirming;

  @override
  ConsumerState<LiveWorkoutScreen> createState() => _LiveWorkoutScreenState();
}

class _LiveWorkoutScreenState extends ConsumerState<LiveWorkoutScreen> {
  late bool _confirming = widget.initialConfirming;
  bool _resumeOnCancel = false;

  WorkoutController get _controller => ref.read(workoutProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final l10n = MetricFormat.of(context).l10n;
    final state = ref.watch(workoutProvider);
    final snapshot = state.snapshot;
    if (snapshot == null) {
      return AppPage(
        title: l10n.workoutPickTitle,
        children: [
          EmptyStateCard(
            key: LiveWorkoutKeys.none,
            icon: Icons.directions_run_rounded,
            accent: AppColors.of(context).activity,
            title: l10n.workoutNoneTitle,
            message: l10n.workoutNoneBody,
            actionLabel: l10n.workoutChoose,
            onAction: () => context.go(AppPaths.workout),
          ),
        ],
      );
    }
    final session = _controller.session;
    final now = ref.read(clockProvider)();
    final route = session?.route;
    final confirming = _confirming && state.live;
    return AppPage(
      title: snapshot.type.label(l10n),
      children: [
        _LinkLine(state: state),
        const SizedBox(height: 12),
        _ClockBlock(snapshot: snapshot),
        const SizedBox(height: 12),
        if (snapshot.gps) ...[
          _MapCard(state: state, route: route, now: now),
          const SizedBox(height: 12),
        ],
        if (state.live) ...[
          _HeartCard(
            state: state,
            zones: session?.profile.zones,
            onReconnect: () => unawaited(_controller.reconnectHeartRate()),
          ),
          const SizedBox(height: 12),
        ],
        _MetricGrid(snapshot: snapshot),
        const SizedBox(height: 20),
        ..._footer(state, confirming),
      ],
    );
  }

  List<Widget> _footer(WorkoutState state, bool confirming) {
    if (confirming) {
      return [
        _ConfirmCard(
          indoor: !(state.snapshot?.gps ?? false),
          onKeepGoing: _cancelEnd,
          onSave: () => unawaited(_save()),
          onDiscard: () => unawaited(_discard()),
        ),
      ];
    }
    if (state.live) return [_Controls(state: state, onEnd: _askEnd)];
    if (state.status == WorkoutStatus.discarded) {
      return [const _DiscardedCard()];
    }
    return [_SaveCard(state: state, onRetry: _controller.saveAgain)];
  }

  void _askEnd() {
    final running = ref.read(workoutProvider).status == WorkoutStatus.running;
    _controller.pause();
    setState(() {
      _confirming = true;
      _resumeOnCancel = running;
    });
  }

  void _cancelEnd() {
    if (_resumeOnCancel) _controller.resume();
    setState(() => _confirming = false);
  }

  Future<void> _save() async {
    setState(() => _confirming = false);
    await _controller.finish();
  }

  Future<void> _discard() async {
    setState(() => _confirming = false);
    await _controller.discard();
  }
}

class _LinkLine extends StatelessWidget {
  const new({required this.state});

  final WorkoutState state;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    final link = ringLinkOf(state);
    return Semantics(
      liveRegion: true,
      child: DotLabel(
        key: LiveWorkoutKeys.link,
        color: link.color(colors),
        text: link.label(l10n),
      ),
    );
  }
}

class _ClockBlock extends StatelessWidget {
  const new({required this.snapshot});

  final WorkoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final clock = format.elapsedClock(snapshot.elapsed);
    final phase = switch (snapshot.status) {
      WorkoutStatus.idle || WorkoutStatus.running => l10n.workoutPhaseRunning,
      WorkoutStatus.paused => l10n.workoutPhasePaused,
      WorkoutStatus.finished => l10n.workoutPhaseFinished,
      WorkoutStatus.discarded => l10n.workoutPhaseDiscarded,
    };
    return Column(
      children: [
        CaptionText(
          key: LiveWorkoutKeys.phase,
          phase,
          textAlign: TextAlign.center,
        ),
        Semantics(
          label: clock,
          excludeSemantics: true,
          child: Text(
            clock.replaceFirst(':', ':\u200B'),
            key: LiveWorkoutKeys.clock,
            textAlign: TextAlign.center,
            style: numberStyle(theme.textTheme.displayMedium),
          ),
        ),
      ],
    );
  }
}

class _MapCard extends ConsumerWidget {
  const new({required this.state, required this.route, required this.now});

  final WorkoutState state;
  final WorkoutRoute? route;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final units = UnitFormat.of(context, ref);
    final l10n = units.l10n;
    final problem = state.locationProblem;
    if (problem != null) {
      final controller = ref.read(workoutProvider.notifier);
      return NoticeCard(
        key: LiveWorkoutKeys.gpsProblem,
        icon: Icons.location_off_outlined,
        accent: colors.heart,
        title: problem == LocationProblem.failed
            ? l10n.workoutGpsLost
            : l10n.workoutGpsOff,
        body: locationProblemMessage(l10n, problem),
        actions: [
          if (problem != LocationProblem.failed)
            SecondaryButton(
              key: LiveWorkoutKeys.settings,
              label: l10n.workoutLocationOpenSettings,
              onPressed: () => unawaited(_openSettings(ref, problem)),
            ),
          if (state.live)
            SecondaryButton(
              key: LiveWorkoutKeys.gpsRetry,
              label: l10n.workoutLocationRetry,
              onPressed: () => unawaited(controller.retryLocation()),
            ),
        ],
      );
    }
    final recorded = route;
    final segments = recorded?.segments ?? const <List<TrackPoint>>[];
    final last = recorded == null ? null : lastPointOf(recorded);
    final quality = gpsQualityOf(status: state.status, now: now, last: last);
    return MetricCard(
      key: LiveWorkoutKeys.map,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _GpsChip(
                quality: quality,
                accuracy: last?.accuracyMeters,
                units: units,
              ),
            ),
          ),
          RouteMap(
            segments: segments,
            live: true,
            semanticsLabel: units.mapSemantics(
              state.snapshot?.distanceMeters ?? 0,
            ),
          ),
          if (segments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: CaptionText(l10n.workoutMapEmpty),
            ),
        ],
      ),
    );
  }

  static Future<void> _openSettings(WidgetRef ref, LocationProblem problem) {
    final access = ref.read(locationAccessProvider);
    if (problem == LocationProblem.serviceDisabled) {
      return access.openLocationSettings();
    }
    return access.openAppSettings();
  }
}

class _GpsChip extends StatelessWidget {
  const new({
    required this.quality,
    required this.accuracy,
    required this.units,
  });

  final GpsQuality quality;
  final double? accuracy;
  final UnitFormat units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = units.l10n;
    final meters = accuracy;
    return Semantics(
      key: LiveWorkoutKeys.gps,
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.strongBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.signal_cellular_alt_rounded,
                size: 14,
                color: quality.color(colors),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: quality.label(l10n),
                    children: [
                      if (quality.showsAccuracy && meters != null)
                        TextSpan(
                          text: '  ${units.gpsAccuracy(meters)}',
                          style: TextStyle(color: colors.textLabel),
                        ),
                    ],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeartCard extends StatelessWidget {
  const new({
    required this.state,
    required this.zones,
    required this.onReconnect,
  });

  final WorkoutState state;
  final HeartRateZones? zones;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final snapshot = state.snapshot;
    final link = ringLinkOf(state);
    final bpm = link.failed ? null : snapshot?.currentHeartRate;
    final zone = link.failed ? null : snapshot?.currentZone;
    final zoneTable = zones;
    return MetricCard(
      key: LiveWorkoutKeys.heart,
      child: Column(
        children: [
          MergeSemantics(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Icon(Icons.favorite_rounded, size: 22, color: colors.heart),
                Text(
                  format.optionalInteger(bpm),
                  style: numberStyle(
                    theme.textTheme.displayLarge,
                    color: bpm == null ? colors.textLabel : colors.heart,
                  ),
                ),
                CaptionText(l10n.workoutUnitBpm),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _caption(l10n, bpm, zone),
            key: LiveWorkoutKeys.zoneCaption,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          ZoneBar(
            zone: zone,
            semanticsLabel: zone == null
                ? l10n.workoutZoneBarNone
                : l10n.workoutZoneBarSemantics(zone),
          ),
          const SizedBox(height: 10),
          if (link.heartMessage(l10n) case final message?)
            CaptionText(message, textAlign: TextAlign.center),
          if (link.heartMessage(l10n) == null)
            CaptionText(
              zoneTable == null
                  ? l10n.workoutZonesMissing
                  : l10n.workoutZonesFromMax(
                      format.integer(zoneTable.maxHeartRate),
                    ),
              textAlign: TextAlign.center,
            ),
          if (link.reconnects) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SecondaryButton(
                key: LiveWorkoutKeys.reconnect,
                label: l10n.workoutHeartReconnect,
                color: colors.heart,
                onPressed: onReconnect,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _caption(AppLocalizations l10n, int? bpm, int? zone) {
    if (bpm == null) return l10n.workoutHeartWaiting;
    if (zone == null) return l10n.workoutZoneBelow;
    return l10n.workoutZoneCaption(zone, zoneName(l10n, zone));
  }
}

class _MetricGrid extends ConsumerWidget {
  const new({required this.snapshot});

  final WorkoutSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = UnitFormat.of(context, ref);
    final format = units.format;
    final l10n = format.l10n;
    final type = snapshot.type;
    final speed = type.showsSpeed;
    final paceUnit = units.paceOrSpeedUnit(type);
    return WorkoutGrid(
      key: LiveWorkoutKeys.metrics,
      children: [
        if (snapshot.gps) ...[
          WorkoutMetricTile(
            label: l10n.workoutDistance,
            value: units.distance(snapshot.distanceMeters),
            unit: units.distanceUnit,
          ),
          WorkoutMetricTile(
            label: speed ? l10n.workoutCurrentSpeed : l10n.workoutCurrentPace,
            value: units.paceOrSpeed(type, snapshot.currentPace),
            unit: paceUnit,
          ),
          WorkoutMetricTile(
            label: speed ? l10n.workoutAverageSpeed : l10n.workoutAveragePace,
            value: units.paceOrSpeed(type, snapshot.averagePace),
            unit: paceUnit,
          ),
        ],
        WorkoutMetricTile(
          label: l10n.workoutEnergy,
          value: format.optionalInteger(snapshot.activeKilocalories),
          unit: l10n.workoutUnitKcal,
        ),
        WorkoutMetricTile(
          label: l10n.workoutAverageHeartRate,
          value: format.optionalInteger(snapshot.averageHeartRate),
          unit: l10n.workoutUnitBpm,
        ),
        WorkoutMetricTile(
          label: l10n.workoutMaxHeartRate,
          value: format.optionalInteger(snapshot.maxHeartRate),
          unit: l10n.workoutUnitBpm,
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const new({required this.state, required this.onEnd});

  final WorkoutState state;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    final controller = ref.read(workoutProvider.notifier);
    final running = state.status == WorkoutStatus.running;
    return ButtonPair(
      first: SecondaryButton(
        key: LiveWorkoutKeys.toggle,
        label: running ? l10n.workoutPause : l10n.workoutResume,
        onPressed: running ? controller.pause : controller.resume,
      ),
      second: AccentButton(
        key: LiveWorkoutKeys.end,
        label: l10n.workoutEnd,
        color: colors.heart,
        onPressed: onEnd,
      ),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  const new({
    required this.indoor,
    required this.onKeepGoing,
    required this.onSave,
    required this.onDiscard,
  });

  final bool indoor;
  final VoidCallback onKeepGoing;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    final platform = workoutHealthPlatform();
    return NoticeCard(
      key: LiveWorkoutKeys.confirm,
      icon: Icons.flag_outlined,
      accent: colors.heart,
      border: colors.strongBorder,
      title: l10n.workoutConfirmTitle,
      body: indoor
          ? l10n.workoutConfirmBodyIndoor(platform)
          : l10n.workoutConfirmBody(platform),
      actions: [
        ButtonPair(
          first: SecondaryButton(
            key: LiveWorkoutKeys.keepGoing,
            label: l10n.workoutContinue,
            onPressed: onKeepGoing,
          ),
          second: AccentButton(
            key: LiveWorkoutKeys.save,
            label: l10n.workoutSave,
            color: colors.heart,
            onPressed: onSave,
          ),
        ),
        TextButton(
          key: LiveWorkoutKeys.discard,
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 48),
            foregroundColor: colors.heart,
          ),
          onPressed: onDiscard,
          child: Text(l10n.workoutDiscard, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

class _SaveCard extends ConsumerWidget {
  const new({required this.state, required this.onRetry});

  final WorkoutState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return switch (state.save) {
      WorkoutSave.none || WorkoutSave.saving => NoticeCard(
        key: LiveWorkoutKeys.saving,
        icon: Icons.save_outlined,
        accent: colors.textSecondary,
        title: l10n.workoutSavingTitle,
      ),
      WorkoutSave.saved => NoticeCard(
        key: LiveWorkoutKeys.saved,
        icon: Icons.check_circle_outline_rounded,
        accent: colors.activity,
        border: colors.activity,
        title: l10n.workoutSavedTitle,
        body: l10n.workoutSavedBody(
          _savedAt(format, state.snapshot?.end),
          workoutHealthPlatform(),
        ),
        actions: [
          ActionButton(
            key: LiveWorkoutKeys.summary,
            label: l10n.workoutViewSummary,
            onPressed: () => context.go(AppPaths.workoutSummary),
          ),
        ],
      ),
      WorkoutSave.failed => NoticeCard(
        key: LiveWorkoutKeys.failed,
        icon: Icons.error_outline_rounded,
        accent: colors.heart,
        title: l10n.workoutSaveFailedTitle,
        body: l10n.workoutSaveFailedBody,
        actions: [
          ActionButton(
            key: LiveWorkoutKeys.retry,
            label: l10n.workoutSaveRetry,
            onPressed: () => unawaited(onRetry()),
          ),
        ],
      ),
    };
  }

  static String _savedAt(MetricFormat format, DateTime? end) {
    if (end == null) return format.l10n.workoutNoValue;
    return format.clock(end, end.toLocal().timeZoneOffset);
  }
}

class _DiscardedCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return NoticeCard(
      key: LiveWorkoutKeys.discarded,
      icon: Icons.delete_outline_rounded,
      accent: colors.textLabel,
      title: l10n.workoutDiscardedTitle,
      body: l10n.workoutDiscardedBody,
      actions: [
        ActionButton(
          label: l10n.workoutBackToActivity,
          onPressed: () => context.go(AppTab.activity.path),
        ),
      ],
    );
  }
}
