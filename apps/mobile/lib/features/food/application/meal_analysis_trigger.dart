import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';

/// Drains the photo queue on start, on resume, and when the AI config, the
/// photo consent or the module list changes. In the background a request
/// already sent finishes, since it may be billed; a photo still being
/// prepared goes back to the queue unsent.
final mealAnalysisTriggerProvider = Provider<void>((ref) {
  MealAnalysisQueue queue() => ref.read(mealAnalysisQueueProvider.notifier);
  void pass() {
    if (!ref.mounted) return;
    unawaited(
      queue().drain().catchError((Object error) {
        debugPrint('Meal analysis pass failed: $error');
      }),
    );
  }

  ref
    ..listen(mealAnalysisQueueProvider, (_, _) {})
    ..listen(aiConfigProvider, (_, _) => pass())
    ..listen(aiMealPhotoConsentProvider, (_, _) => pass())
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
