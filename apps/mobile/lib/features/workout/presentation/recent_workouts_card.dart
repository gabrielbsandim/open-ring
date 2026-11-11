import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/settings/presentation/source_labels.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/features/workout/presentation/workout_routes.dart';

abstract final class RecentWorkoutsKeys {
  static const card = Key('recent_workouts');
  static const empty = Key('recent_workouts_empty');
  static const error = Key('recent_workouts_error');

  static Key item(int id) => Key('recent_workout_$id');

  static Key importedItem(String recordId) =>
      Key('recent_workout_imported_$recordId');
}

Key _keyOf(WorkoutEntry workout) => switch (workout) {
  WorkoutListItem(:final id) => RecentWorkoutsKeys.item(id),
  ImportedWorkout(:final recordId) => RecentWorkoutsKeys.importedItem(recordId),
};

class RecentWorkoutsCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    final value = ref.watch(recentWorkoutsProvider);
    final workouts = value.value;
    if (workouts == null && value.hasError) {
      return MetricCard(
        key: RecentWorkoutsKeys.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccentTitle(title: l10n.workoutRecentTitle, accent: colors.heart),
            const SizedBox(height: 6),
            BodyText(key: RecentWorkoutsKeys.error, l10n.metricLoadError),
          ],
        ),
      );
    }
    if (workouts == null) return const SizedBox.shrink();
    return MetricCard(
      key: RecentWorkoutsKeys.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: l10n.workoutRecentTitle, accent: colors.activity),
          const SizedBox(height: 6),
          if (workouts.isEmpty)
            BodyText(
              key: RecentWorkoutsKeys.empty,
              l10n.workoutRecentEmptyHint(l10n.workoutStart),
            ),
          for (var i = 0; i < workouts.length; i++)
            _WorkoutRow(
              key: _keyOf(workouts[i]),
              workout: workouts[i],
              divided: i < workouts.length - 1,
            ),
        ],
      ),
    );
  }
}

class _WorkoutRow extends ConsumerWidget {
  const new({required this.workout, required this.divided, super.key});

  final WorkoutEntry workout;
  final bool divided;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final today = ref.watch(currentDateProvider);
    final day = format.workoutDay(workout.start, workout.utcOffset, today);
    final duration = format.duration(workout.elapsed);
    final bpm = switch (workout) {
      WorkoutListItem(:final averageHeartRate) => averageHeartRate,
      ImportedWorkout() => null,
    };
    final details = bpm == null
        ? l10n.workoutRecentLineNoHeart(day, duration)
        : l10n.workoutRecentLine(day, duration, format.integer(bpm));
    final title = Text(
      workout.type.label(l10n),
      style: theme.textTheme.bodyLarge,
    );
    final (statusText, statusColor) = switch (workout) {
      WorkoutListItem(:final health) => (
        health.label(l10n),
        health.color(colors),
      ),
      ImportedWorkout(:final source) => (
        l10n.workoutImportedFrom(sourceName(source, l10n)),
        colors.textSecondary,
      ),
    };
    final path = switch (workout) {
      WorkoutListItem(:final id) => workoutSummaryPath(id),
      ImportedWorkout(:final recordId) => importedWorkoutPath(recordId),
    };
    final status = Text(
      statusText,
      style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        CaptionText(details),
        if (context.prefersSingleColumn) ...[const SizedBox(height: 2), status],
      ],
    );
    return MergeSemantics(
      child: InkWell(
        onTap: () => context.go(path),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: divided
                ? Border(bottom: BorderSide(color: colors.surfaceBorder))
                : null,
          ),
          child: Row(
            children: [
              Expanded(child: text),
              if (!context.prefersSingleColumn) ...[
                const SizedBox(width: 12),
                Flexible(child: status),
              ],
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.textLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
