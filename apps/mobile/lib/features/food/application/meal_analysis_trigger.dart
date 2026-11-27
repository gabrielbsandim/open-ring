import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/vision_probe_controller.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';

/// Drains the photo queue on start, on resume, and when the AI config, the
/// photo consent, the photo vision result or the module list changes. In the
/// background a request already sent finishes, since it may be billed; a
/// photo still being prepared goes back to the queue unsent.
final mealAnalysisTriggerProvider = Provider<void>((ref) {
  MealAnalysisQueue queue() => ref.read(mealAnalysisQueueProvider.notifier);
  void pass() {
    if (!ref.mounted) return;
    unawaited(queue().drain());
  }

  // A launch while hidden sends no lifecycle event until the next change.
  final now = WidgetsBinding.instance.lifecycleState;
  if (now != null && now != AppLifecycleState.resumed) queue().toBackground();
  ref
    ..listen(mealAnalysisQueueProvider, (_, _) {})
    ..listen(aiConfigProvider, (_, _) => pass())
    ..listen(aiMealPhotoConsentProvider, (_, _) => pass())
    ..listen(aiPhotoVisionProvider, (_, _) => pass())
    ..listen(enabledModulesProvider, (_, _) => pass(), fireImmediately: true);
  final listener = AppLifecycleListener(
    onResume: () {
      queue().toForeground();
      pass();
    },
    onHide: () => queue().toBackground(),
    onPause: () => queue().toBackground(),
  );
  ref.onDispose(listener.dispose);
});
