import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/presentation/workout_widgets.dart';

class WorkoutEntryButton extends ConsumerWidget {
  const new({super.key});

  static const startKey = Key('workout_entry_start');
  static const liveKey = Key('workout_entry_live');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    if (ref.watch(workoutProvider.select((state) => state.live))) {
      return AccentButton(
        key: liveKey,
        label: l10n.workoutBackToLive,
        icon: Icons.timer_outlined,
        color: colors.heart,
        onPressed: () => context.go(AppPaths.workoutLive),
      );
    }
    return AccentButton(
      key: startKey,
      label: l10n.workoutStart,
      icon: Icons.play_arrow_rounded,
      color: colors.activity,
      onPressed: () => context.go(AppPaths.workout),
    );
  }
}
