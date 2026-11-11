import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/workout/application/location_access_provider.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/features/workout/presentation/workout_routes.dart';
import 'package:open_ring/features/workout/presentation/workout_widgets.dart';

abstract final class WorkoutPickKeys {
  static const ring = Key('workout_pick_ring');
  static const detail = Key('workout_pick_detail');
  static const start = Key('workout_pick_start');
  static const gps = Key('workout_pick_gps');
  static const swimming = Key('workout_pick_swimming');

  static Key type(WorkoutType type) => Key('workout_pick_${type.name}');
}

class WorkoutPickScreen extends ConsumerStatefulWidget {
  const new({this.initialType = WorkoutType.running, super.key});

  final WorkoutType initialType;

  @override
  ConsumerState<WorkoutPickScreen> createState() => _WorkoutPickScreenState();
}

class _WorkoutPickScreenState extends ConsumerState<WorkoutPickScreen> {
  late WorkoutType _type = widget.initialType;
  bool? _gps;
  bool _starting = false;

  bool get _gpsOn => _type.allowsGps(requested: _gps ?? _type.gpsByDefault);

  @override
  Widget build(BuildContext context) {
    final l10n = MetricFormat.of(context).l10n;
    final colors = AppColors.of(context);
    final lastType = ref.watch(lastWorkoutProvider).value?.type;
    return AppPage(
      title: l10n.workoutPickTitle,
      children: [
        _RingLine(status: ref.watch(ringStatusProvider).value),
        const SizedBox(height: 16),
        Semantics(
          container: true,
          label: l10n.workoutPickTypes,
          child: WorkoutGrid(
            children: [
              for (final type in WorkoutType.values)
                _TypeTile(
                  key: WorkoutPickKeys.type(type),
                  type: type,
                  selected: type == _type,
                  last: type == lastType,
                  onTap: () => setState(() {
                    _type = type;
                    _gps = null;
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _SwimmingRow(key: WorkoutPickKeys.swimming),
        const SizedBox(height: 14),
        _DetailCard(
          key: WorkoutPickKeys.detail,
          type: _type,
          gps: _gpsOn,
          onGps: (value) => setState(() => _gps = value),
        ),
        const SizedBox(height: 24),
        AccentButton(
          key: WorkoutPickKeys.start,
          label: l10n.workoutBegin,
          icon: Icons.play_arrow_rounded,
          color: colors.activity,
          onPressed: _starting ? null : () => unawaited(_start()),
        ),
      ],
    );
  }

  Future<void> _start() async {
    final router = GoRouter.of(context);
    final type = _type;
    final gps = _gpsOn;
    if (ref.read(workoutProvider).live) {
      router.go(AppPaths.workoutLive);
      return;
    }
    setState(() => _starting = true);
    final ready = !gps || await _locationGranted();
    if (!mounted) return;
    if (!ready) {
      setState(() => _starting = false);
      router.go(workoutLocationPath(type));
      return;
    }
    await _begin(router, type, gps: gps);
  }

  // A status the phone cannot report sends the user to the explainer, where
  // asking again or training without GPS is still possible.
  Future<bool> _locationGranted() async {
    try {
      return (await ref.read(locationAccessProvider).status()).isGranted;
    } on Object {
      return false;
    }
  }

  Future<void> _begin(
    GoRouter router,
    WorkoutType type, {
    required bool gps,
  }) async {
    final notice = workoutLocationNotice(MetricFormat.of(context).l10n);
    await beginWorkout(ref, router, type, notice: notice, gps: gps);
    if (!mounted) return;
    setState(() => _starting = false);
  }
}

class _RingLine extends StatelessWidget {
  const new({required this.status});

  final RingStatus? status;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final ring = status;
    if (ring == null) return const SizedBox.shrink();
    if (!ring.paired) {
      return DotLabel(
        key: WorkoutPickKeys.ring,
        color: colors.stress,
        text: l10n.workoutRingMissing,
      );
    }
    final battery = ring.batteryPercent;
    return DotLabel(
      key: WorkoutPickKeys.ring,
      color: colors.activity,
      text: battery == null
          ? l10n.workoutRingPaired
          : l10n.workoutRingBattery(format.percent(battery.toDouble())),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const new({
    required this.type,
    required this.selected,
    required this.last,
    required this.onTap,
    super.key,
  });

  final WorkoutType type;
  final bool selected;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    final single = context.prefersSingleColumn;
    final icon = Icon(
      type.icon,
      size: 26,
      color: selected ? colors.activity : colors.textSecondary,
    );
    final label = Text(
      type.label(l10n),
      textAlign: single ? TextAlign.start : TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: selected ? colors.textPrimary : colors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : null,
      ),
    );
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: single
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        label,
        if (last) CaptionText(l10n.workoutLastBadge, color: colors.activity),
      ],
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.surfaceInner : colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? colors.activity : colors.surfaceBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: single ? 56 : 96),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: single
                  ? Row(
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        Expanded(child: text),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [icon, const SizedBox(height: 8), text],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwimmingRow extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return MergeSemantics(
      child: Semantics(
        enabled: false,
        child: MetricCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.pool_rounded, size: 26, color: colors.textLabel),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.workoutSwimmingUnavailable,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    CaptionText(l10n.workoutSwimmingReason),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const new({
    required this.type,
    required this.gps,
    required this.onGps,
    super.key,
  });

  final WorkoutType type;
  final bool gps;
  final ValueChanged<bool> onGps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.workoutRecordedTitle(type.label(l10n)),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                BodyText(type.recorded(l10n)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: colors.surfaceBorder),
          if (type.gpsChoosable)
            SwitchListTile(
              key: WorkoutPickKeys.gps,
              value: gps,
              onChanged: onGps,
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                Icons.location_on_outlined,
                size: 20,
                color: gps ? colors.activity : colors.textLabel,
              ),
              title: Text(
                l10n.workoutGpsToggle,
                style: theme.textTheme.bodyMedium,
              ),
              activeThumbColor: colors.background,
              activeTrackColor: colors.activity,
              inactiveThumbColor: colors.textSecondary,
              inactiveTrackColor: colors.surfaceInner,
            ),
          if (!type.gpsChoosable) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!type.gpsChoosable) ...[
                Icon(
                  Icons.location_off_outlined,
                  size: 20,
                  color: colors.textLabel,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(child: CaptionText(type.gpsNote(l10n, gps: gps))),
            ],
          ),
        ],
      ),
    );
  }
}
