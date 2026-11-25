import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/application/meal_analysis_view.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class MealPhotoPauseKeys {
  static const card = Key('meal_photo_pause_card');
  static const connection = Key('meal_photo_pause_connection');
  static const resume = Key('meal_photo_pause_resume');
  static const test = Key('meal_photo_pause_test');
}

/// Drawn only while a stored pause holds. A noVision pause offers the photo
/// test instead of Resume, which leaves that pause in place.
class MealPhotoPauseCard extends ConsumerWidget {
  const new({required this.onTest, this.locked = false, super.key});

  final VoidCallback onTest;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pause = ref.watch(aiPhotoQueuePauseProvider).value;
    if (pause == null) return const SizedBox.shrink();
    final count = ref.watch(mealPhotoQueuedCountProvider).value ?? 0;
    final l10n = AppLocalizations.of(context);
    final detail = switch (pause.reason) {
      AiPhotoQueuePauseReason.unauthorized => l10n.aiErrorKey,
      AiPhotoQueuePauseReason.noCredit => l10n.aiErrorNoCredit,
      AiPhotoQueuePauseReason.forbidden => l10n.aiErrorForbidden(pause.model),
      AiPhotoQueuePauseReason.noVision => l10n.aiPhotosVisionState(
        'no',
        pause.model,
      ),
    };
    final queue = ref.read(mealAnalysisQueueProvider.notifier);
    return MetricCard(
      key: MealPhotoPauseKeys.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.aiPhotosPausedTitle(count),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          BodyText(l10n.aiPhotosPausedBody),
          const SizedBox(height: 8),
          CaptionText(detail),
          const SizedBox(height: 12),
          ActionButton(
            buttonKey: MealPhotoPauseKeys.connection,
            label: l10n.aiGuideOpen,
            onPressed: () => unawaited(
              GoRouter.maybeOf(context)?.push(AppPaths.settingsAiConnection),
            ),
          ),
          const SizedBox(height: 8),
          if (pause.reason == AiPhotoQueuePauseReason.noVision)
            SecondaryButton(
              buttonKey: MealPhotoPauseKeys.test,
              label: l10n.aiPhotosVisionTest,
              onPressed: locked ? null : onTest,
            )
          else
            SecondaryButton(
              buttonKey: MealPhotoPauseKeys.resume,
              label: l10n.aiPhotosResume(count),
              onPressed: locked ? null : () => unawaited(queue.resume()),
            ),
          const SizedBox(height: 12),
          CaptionText(l10n.aiPhotosExpiry),
        ],
      ),
    );
  }
}
