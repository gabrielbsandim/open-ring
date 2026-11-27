import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/goal_reword_controller.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';

final aiDataEraserProvider = Provider<AiDataEraser>(AiDataEraser.new);

/// Remove key and readings. Keeps the month token counter, the photo day
/// uses, the Food range opt in, meals and the module switch.
class AiDataEraser {
  const new(this._ref);

  final Ref _ref;

  /// Runs are aborted first and the key goes last, as in Delete all data, so
  /// a keystore failure returns false only after the readings are gone.
  Future<bool> clear() async {
    final runs = [
      _ref.read(analysisRunControllerProvider.notifier).idle,
      _ref.read(mealAnalysisQueueProvider.notifier).idle,
    ];
    _ref
      ..invalidate(analysisRunControllerProvider)
      ..invalidate(mealAnalysisQueueProvider)
      ..invalidate(goalRewordControllerProvider);
    await Future.wait(runs)
        .timeout(aiRunAbortWait, onTimeout: () => [])
        .catchError((Object _) => <void>[]);
    try {
      await _ref.read(aiReportStoreProvider).deleteAll();
      await _ref.read(mealAnalysisStoreProvider).deleteAll();
      await _ref.read(aiRunMarkerStoreProvider).clear();
      await _ref.read(aiConfigProvider.notifier).clearAll();
      return true;
    } on Object catch (error) {
      debugPrint('AI data was not fully removed: $error');
      return false;
    } finally {
      _ref
        ..invalidate(aiConsentProvider)
        ..invalidate(aiMealPhotoConsentProvider)
        ..invalidate(aiAvailabilityProvider)
        ..invalidate(aiRecentReportsProvider);
      _ref.read(dataRevisionProvider.notifier).bump();
    }
  }
}
