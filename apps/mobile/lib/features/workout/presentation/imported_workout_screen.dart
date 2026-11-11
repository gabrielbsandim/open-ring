import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/settings/presentation/source_labels.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/features/workout/presentation/workout_widgets.dart';

abstract final class ImportedWorkoutKeys {
  static const duration = Key('imported_workout_duration');
  static const source = Key('imported_workout_source');
  static const missing = Key('imported_workout_missing');
  static const back = Key('imported_workout_back');
}

// Read only: an imported workout belongs to the app that recorded it, so
// there is no delete, and no GPX because its route is never read.
class ImportedWorkoutScreen extends ConsumerWidget {
  const new({required this.recordId, super.key});

  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = MetricFormat.of(context).l10n;
    final value = ref.watch(importedWorkoutProvider(recordId));
    if (!value.hasValue) {
      return AppPage(
        title: l10n.workoutSummaryTitle,
        children: [
          AsyncBody(value: value, builder: (_) => const SizedBox.shrink()),
        ],
      );
    }
    final workout = value.requireValue;
    if (workout == null) return const _MissingView();
    return _ImportedSummary(workout: workout);
  }
}

class _MissingView extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return AppPage(
      title: l10n.workoutSummaryTitle,
      children: [
        EmptyStateCard(
          key: ImportedWorkoutKeys.missing,
          icon: Icons.directions_run_rounded,
          accent: colors.activity,
          message: l10n.workoutSummaryMissing,
          actionLabel: l10n.workoutBackToActivity,
          onAction: () => context.go(AppTab.activity.path),
        ),
      ],
    );
  }
}

class _ImportedSummary extends StatelessWidget {
  const new({required this.workout});

  final ImportedWorkout workout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final offset = workout.utcOffset;
    final app = sourceName(workout.source, l10n);
    return AppPage(
      title: workout.type.label(l10n),
      subtitle: l10n.workoutSummaryWhen(
        format.date(LocalDate.fromInstant(workout.start, offset)),
        format.clock(workout.start, offset),
        format.clock(workout.end, offset),
      ),
      children: [
        MergeSemantics(
          key: ImportedWorkoutKeys.duration,
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
        const SizedBox(height: 16),
        NoticeCard(
          key: ImportedWorkoutKeys.source,
          icon: Icons.download_rounded,
          accent: colors.textSecondary,
          title: l10n.workoutImportedFrom(app),
          body: l10n.workoutImportedBody(workoutHealthPlatform(), app),
        ),
        const SizedBox(height: 8),
        CaptionText(l10n.workoutImportedNote(app)),
        const SizedBox(height: 20),
        SecondaryButton(
          key: ImportedWorkoutKeys.back,
          label: l10n.workoutBackToActivity,
          onPressed: () => context.go(AppTab.activity.path),
        ),
      ],
    );
  }
}
